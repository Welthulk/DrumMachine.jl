# Audio engine: sample-accurate sequencer + voice mixer. The same `render!` function is
# used for live playback (PortAudio) and WAV export.

import PortAudio
using Random: MersenneTwister, AbstractRNG

const BLOCK = 512
const NVOICES = 64
const FADE_SAMPLES = round(Int, 0.008 * SR)     # fade time when choking (hi-hat choke)

# Velocity level (ghost note, normal, accent) -> share of kit layers (soft → loud)
const LEVEL_RANGE = ((0.0, 0.4), (0.4, 0.8), (0.8, 1.0))

"Layer indices (1…nl) for velocity level `level`; with 5 layers: 1–2, 3–4, 5."
function level_layers(level::Int, nl::Int)
    f0, f1 = LEVEL_RANGE[level]
    lo = min(nl, floor(Int, f0 * nl) + 1)
    hi = clamp(round(Int, f1 * nl), lo, nl)
    return lo:hi
end

mutable struct Voice
    buf::Vector{Float32}
    bufr::Vector{Float32}  # right channel (=== buf for mono samples)
    pos::Float64
    rate::Float64
    gl::Float32
    gr::Float32
    track::Int
    choke::Int
    fade::Int            # > 0: fading out (remaining samples)
    active::Bool
end
Voice() = (b = Float32[]; Voice(b, b, 0.0, 1.0, 0f0, 0f0, 0, 0, 0, false))

"""
Playback of a WAV from the editor. Mixed in after master effect and limiter, so the file is heard
unchanged. `pos` is a fractional frame position in the source (its own sample rate).
"""
mutable struct Preview
    data::Matrix{Float32}
    fs::Int
    pos::Float64
    stop::Int                        # last frame to play
    loop_from::Int                   # loop start frame
    loop::Bool
    on::Bool
    shown::Threads.Atomic{Int}       # current frame for the GUI (0 = not playing)
end
Preview() = Preview(zeros(Float32, 0, 1), SR, 1.0, 0, 1, false, false, Threads.Atomic{Int}(0))

mutable struct Engine
    song::Song
    kit::Kit
    voices::Vector{Voice}
    last::Vector{Sample}             # last sample played per track (no immediate repeat)
    rng::MersenneTwister             # seeded → exports are reproducible
    fx::FXState
    trackfx::Vector{TrackFX}         # EQ/chorus/flanger per track
    bus::Vector{Matrix{Float32}}     # track buses (only used for tracks with effects)
    fxon::Vector{Bool}               # track runs through its bus in the current block
    click_hi::Sample
    click_lo::Sample
    # Transport
    playing::Bool
    samplepos::Int
    next_step_at::Float64
    step::Int                        # next step (0-based)
    seq::Vector{Int}                 # bars: 0 = count-in, -1 = current edit pattern, else pattern index
    seqpos::Int
    loop_from::Int                   # 0 = stop at the end
    pat::Int                         # playing pattern (0 = count-in)
    edit_pat::Int
    songmode::Bool
    live_countin::Bool
    finished::Bool
    # Display (read by the GUI)
    shown_step::Threads.Atomic{Int}
    shown_pat::Threads.Atomic{Int}
    shown_seqpos::Threads.Atomic{Int}
    # Track preview (filled by the GUI)
    pads::Channel{Tuple{Int,Int}}
    lock::ReentrantLock
    running::Bool
    task::Union{Task,Nothing}
    preview::Preview
end

function Engine(song::Song, kit::Kit)
    fx = FXState()
    nos = Sample(Float32[])
    eng = Engine(song, kit, [Voice() for _ in 1:NVOICES], fill(nos, NTRACKS), MersenneTwister(4711), fx,
                 [TrackFX() for _ in 1:NTRACKS], [zeros(Float32, BLOCK, 2) for _ in 1:NTRACKS], fill(false, NTRACKS),
                 click_sound(true), click_sound(false),
                 false, 0, 0.0, 0, Int[], 1, 0, 1, 1, false, false, false,
                 Threads.Atomic{Int}(-1), Threads.Atomic{Int}(1), Threads.Atomic{Int}(0),
                 Channel{Tuple{Int,Int}}(64), ReentrantLock(), false, nothing, Preview())
    apply_fx!(eng)
    return eng
end

"Applies the FX choice and mix from the song to the effect state."
function apply_fx!(eng::Engine)
    k = findfirst(==(eng.song.fx), FX_NAMES)
    eng.fx.kind = something(k, 1)
    eng.fx.mix = Float32(eng.song.fxmix)
    return eng
end

# ---------------------------------------------------------------------------
# Voices
# ---------------------------------------------------------------------------

function start_voice!(eng::Engine, smp::Sample, gain::Float32, pan::Float32, rate::Float64,
                      track::Int, choke::Int)
    if choke > 0                      # fade out the same choke group
        for v in eng.voices
            if v.active && v.choke == choke && v.fade == 0
                v.fade = FADE_SAMPLES
            end
        end
    end
    v = nothing
    for w in eng.voices
        if !w.active
            v = w; break
        end
    end
    if v === nothing                  # steal the oldest voice
        v = eng.voices[argmax(w.pos for w in eng.voices)]
    end
    p = clamp(pan, -1f0, 1f0)
    v.buf = smp.l; v.bufr = smp.r; v.pos = 0.0; v.rate = rate
    if isstereo(smp)          # stereo sample: balance, center = unchanged
        v.gl = gain * min(1f0, 1f0 - p)
        v.gr = gain * min(1f0, 1f0 + p)
    else                      # mono sample: equal-power panning
        θ = (p + 1f0) * Float32(π) / 4
        v.gl = gain * cos(θ)
        v.gr = gain * sin(θ)
    end
    v.track = track; v.choke = choke; v.fade = 0; v.active = true
    return v
end

"Plays track `t` at velocity level `level` (1–3). `seq=true` honors mute/solo."
function trigger!(eng::Engine, t::Int, level::Int; seq::Bool = true)
    tp = eng.song.tracks[t]
    if seq
        tp.mute && return
        anysolo = any(x -> x.solo, eng.song.tracks)
        anysolo && !tp.solo && return
    end
    kit = eng.kit
    smp = pick_sample(eng.rng, kit.layers[t], level, eng.last[t])
    eng.last[t] = smp
    gain = kit.level_gain[level] * kit.gain[t] * tp.vol
    rate = 2.0^(tp.pitch / 12)
    start_voice!(eng, smp, gain, kit.pan[t] + tp.pan, rate, t, kit.choke[t])
    return
end

"""
Randomly picks a recording from the layers of the velocity level (all round robins),
but not the same one as last time – so fast repeats sound natural.
"""
function pick_sample(rng::AbstractRNG, layers::Vector{Vector{Sample}}, level::Int, prev::Sample)
    r = level_layers(level, length(layers))
    n = sum(length(layers[l]) for l in r)
    k = rand(rng, 1:n)
    s = nth_sample(layers, r, k)
    if s === prev && n > 1                 # no immediate repeat: next recording
        s = nth_sample(layers, r, mod1(k + 1, n))
    end
    return s
end

function nth_sample(layers, r, k)
    for l in r
        k <= length(layers[l]) && return layers[l][k]
        k -= length(layers[l])
    end
    error("Index außerhalb der Layer")   # i18n-ok: internal error, never shown
end

function click!(eng::Engine, accent::Bool)
    start_voice!(eng, accent ? eng.click_hi : eng.click_lo, accent ? 0.7f0 : 0.5f0, 0f0, 1.0, 0, 0)
end

@inline function mix_voices!(eng::Engine, main::Matrix{Float32}, i0::Int, n::Int)
    @inbounds for v in eng.voices
        v.active || continue
        out = 1 <= v.track <= NTRACKS && eng.fxon[v.track] ? eng.bus[v.track] : main
        buf = v.buf; bufr = v.bufr; L = length(buf)
        pos = v.pos; rate = v.rate; gl = v.gl; gr = v.gr; fade = v.fade
        for i in i0:i0+n-1
            ip = unsafe_trunc(Int, pos)
            if ip + 2 > L
                v.active = false; break
            end
            fr = Float32(pos - ip)
            sl = buf[ip+1] * (1f0 - fr) + buf[ip+2] * fr
            sr = bufr[ip+1] * (1f0 - fr) + bufr[ip+2] * fr
            if fade > 0
                f = fade / Float32(FADE_SAMPLES)
                sl *= f; sr *= f
                fade -= 1
                if fade == 0
                    v.active = false; break
                end
            end
            out[i, 1] += sl * gl
            out[i, 2] += sr * gr
            pos += rate
        end
        v.pos = pos; v.fade = fade
    end
end

# ---------------------------------------------------------------------------
# Sequencer
# ---------------------------------------------------------------------------

current_pattern(eng::Engine) = eng.pat == 0 ? countin_pattern(eng) : eng.song.patterns[eng.pat]

"First real pattern of the sequence; determines the length of the count-in."
function countin_pattern(eng::Engine)
    for p in eng.seq
        p > 0 && return eng.song.patterns[p]
        p == -1 && return eng.song.patterns[eng.edit_pat]
    end
    return eng.song.patterns[1]
end

"""
Swing basis for pattern `p`: 8 or 16. With auto (0) it swings on 16ths as soon as the
pattern has hits on 'e' or 'a', otherwise on 8ths.
"""
function swing_unit(song::Song, p::Union{Pattern,Nothing})
    song.swing_on != 0 && return song.swing_on
    p === nothing && return 16
    return any(!iszero, @view p.grid[:, 2:2:p.steps]) ? 16 : 8
end

"""
Duration of step `s` (0-based) in samples, incl. swing. The bar length always stays the same.

Uniform meaning of `song.swing`: position of the off-beat note within its group
(50 % = middle/straight, 67 % = triplet, 75 % = dotted).

- 8th/16th grid: pairs (8th or 16th pair); the first half is stretched by `swing`.
- Triplet grid (3 or 6 per beat): groups of three; the third triplet sits at `swing`
  of the group, the middle one exactly in between. At 2/3 this gives exact triplets.
"""
function step_samples(song::Song, s::Int, p::Union{Pattern,Nothing} = nothing)
    spb = song.steps_per_beat
    base = 60.0 / song.bpm / spb * SR
    sw = clamp(song.swing, 0.5, 0.8)
    if spb in (3, 6)
        g = 3base                                          # duration of a group of three
        return s % 3 == 2 ? (1 - sw) * g : sw * g / 2
    end
    (sw == 0.5 || !(spb in (2, 4))) && return base
    if spb == 2 || swing_unit(song, p) == 16
        return 2base * (iseven(s) ? sw : 1 - sw)          # pairs of single steps
    end
    return 2base * (s % 4 < 2 ? sw : 1 - sw)               # 16th grid, swing on 8ths
end

function resolve_pat(eng::Engine, p::Int)
    p == -1 && return clamp(eng.edit_pat, 1, length(eng.song.patterns))
    p == 0 && return 0
    return clamp(p, 1, length(eng.song.patterns))
end

function do_step!(eng::Engine)
    song = eng.song
    s = eng.step
    if eng.pat == 0
        if s % song.steps_per_beat == 0
            click!(eng, s == 0)
        end
        p = countin_pattern(eng)
        steps = p.steps
    else
        p = song.patterns[eng.pat]
        steps = p.steps
        if s < steps
            for t in 1:NTRACKS
                lv = p.grid[t, s+1]
                lv > 0 && trigger!(eng, t, Int(lv))
            end
        end
        if song.click && s % song.steps_per_beat == 0
            click!(eng, s == 0)
        end
    end
    eng.shown_step[] = s
    eng.shown_pat[] = eng.pat
    eng.shown_seqpos[] = eng.seqpos
    eng.next_step_at += step_samples(song, s, p)
    eng.step += 1
    if eng.step >= steps
        eng.step = 0
        eng.seqpos += 1
        if eng.seqpos > length(eng.seq)
            if eng.loop_from == 0
                eng.playing = false
                eng.finished = true
                eng.shown_step[] = -1
                return
            end
            eng.seqpos = eng.loop_from
        end
        eng.pat = resolve_pat(eng, eng.seq[eng.seqpos])
    end
    return
end

"Starts playback of sequence `seq` (see field docs) right away."
function start_seq!(eng::Engine, seq::Vector{Int}, loop_from::Int)
    eng.seq = seq
    eng.loop_from = loop_from
    eng.seqpos = 1
    eng.pat = resolve_pat(eng, seq[1])
    eng.step = 0
    eng.next_step_at = eng.samplepos + 0.01 * SR
    eng.finished = false
    eng.playing = true
    return eng
end

"Live: pattern mode (current edit pattern looped) or song mode (chain looped)."
function play!(eng::Engine)
    lock(eng.lock) do
        ci = eng.live_countin ? fill(0, eng.song.countin) : Int[]
        body = eng.songmode ? copy(eng.song.chain) : [-1]
        start_seq!(eng, vcat(ci, body), length(ci) + 1)
    end
end

function stop!(eng::Engine)
    lock(eng.lock) do
        eng.playing = false
        eng.shown_step[] = -1
        for v in eng.voices
            v.active && v.fade == 0 && (v.fade = FADE_SAMPLES)
        end
    end
end

"Renders one block (frames × 2) – sample-accurate, steps may fall mid-block."
function render!(eng::Engine, out::Matrix{Float32})
    fill!(out, 0f0)
    while isready(eng.pads)
        t, lv = take!(eng.pads)
        t == 0 ? click!(eng, true) : trigger!(eng, t, lv; seq = false)
    end
    N = size(out, 1)
    for t in 1:NTRACKS                       # track effects: prepare buses
        tp = eng.song.tracks[t]
        eng.fxon[t] = has_trackfx(tp)
        eng.fxon[t] || continue
        size(eng.bus[t], 1) == N || (eng.bus[t] = zeros(Float32, N, 2))
        fill!(eng.bus[t], 0f0)
        update_eq!(eng.trackfx[t], tp.eq_low, tp.eq_mid, tp.eq_midf, tp.eq_high)
    end
    i = 1
    while i <= N
        if eng.playing
            due = eng.next_step_at - eng.samplepos
            if due <= 0
                do_step!(eng)
                continue
            end
            n = min(N - i + 1, ceil(Int, due))
        else
            n = N - i + 1
        end
        mix_voices!(eng, out, i, n)
        eng.samplepos += n
        i += n
    end
    for t in 1:NTRACKS
        eng.fxon[t] && process_track!(eng.trackfx[t], eng.song.tracks[t], eng.bus[t], out, N)
    end
    m = Float32(eng.song.master)
    fx = eng.fx
    @inbounds for k in 1:N
        l, r = process(fx, out[k, 1], out[k, 2])
        if eng.song.mono                    # sum L+R on both channels (level ~ like stereo center)
            l = r = (l + r) * 0.7071f0
        elseif eng.song.swap_lr             # swap channels (e.g. drummer's instead of audience perspective)
            l, r = r, l
        end
        out[k, 1] = tanh(l * m)
        out[k, 2] = tanh(r * m)
    end
    eng.preview.on && mix_preview!(eng.preview, out)
    return out
end

"Adds the editor playback to `out` (linear interpolation, own sample rate, optional loop)."
function mix_preview!(p::Preview, out::Matrix{Float32})
    d = p.data; n = size(d, 1); st = p.fs / SR; c2 = size(d, 2) > 1 ? 2 : 1
    n == 0 && (p.on = false; p.shown[] = 0; return out)
    @inbounds for k in 1:size(out, 1)
        if p.pos >= p.stop + 1
            if p.loop && p.stop >= p.loop_from
                # wrap into the loop, however far the step went past the end (short loops, other fs)
                len = p.stop - p.loop_from + 1
                p.pos = p.loop_from + mod(p.pos - p.loop_from, len)
            else
                p.on = false; p.shown[] = 0
                return out
            end
        end
        i = clamp(unsafe_trunc(Int, p.pos), 1, n); f = Float32(p.pos - i); j = min(i + 1, n)
        out[k, 1] += d[i, 1] * (1f0 - f) + d[j, 1] * f
        out[k, 2] += d[i, c2] * (1f0 - f) + d[j, c2] * f
        p.pos += st
    end
    p.shown[] = unsafe_trunc(Int, p.pos)
    return out
end

"""
    preview_play!(eng, data, fs; from = 1, to = size(data, 1), loop = false)

Starts playing `data` (frames × channels) from frame `from` to `to`; with `loop`, the range
`from:to` repeats. Replaces any running preview.
"""
function preview_play!(eng::Engine, data::Matrix{Float32}, fs::Integer; from::Integer = 1,
                       to::Integer = size(data, 1), loop::Bool = false)
    n = size(data, 1)
    n == 0 && return eng
    a = clamp(from, 1, n); b = clamp(to, a, n)
    lock(eng.lock) do
        p = eng.preview
        p.data = data; p.fs = fs; p.pos = a; p.stop = b; p.loop_from = a; p.loop = loop
        p.on = true; p.shown[] = a
    end
    return eng
end

"Stops the editor playback."
function preview_stop!(eng::Engine)
    lock(eng.lock) do
        eng.preview.on = false; eng.preview.shown[] = 0
    end
    return eng
end

"Send the track bus through EQ and modulation and add it to the sum `out`."
function process_track!(fx::TrackFX, tp::TrackParams, bus::Matrix{Float32}, out::Matrix{Float32}, N::Int)
    eq = has_eq(tp)
    md = tp.mod
    chorus = md == 2
    mix = tp.mod_mix; rate = tp.mod_rate; depth = tp.mod_depth; fb = clamp(tp.mod_fb, 0f0, 0.9f0)
    @inbounds for k in 1:N
        l = bus[k, 1]; r = bus[k, 2]
        if eq
            l, r = process(fx.low, l, r)
            l, r = process(fx.mid, l, r)
            l, r = process(fx.high, l, r)
        end
        if md > 1
            l, r = process(fx.mod, chorus, l, r, mix, rate, depth, fb)
        end
        out[k, 1] += l
        out[k, 2] += r
    end
    return out
end

# ---------------------------------------------------------------------------
# Live audio
# ---------------------------------------------------------------------------

"""
    start_audio!(eng; device = nothing, latency = 0.15)

Opens the audio device and starts the audio thread. `latency` (seconds) is the buffer to the
sound card: chosen generously so that garbage collection pauses (Julia briefly halts all
threads, GLMakie creates a lot of garbage while drawing) don't cause dropouts.
For a practice tool the delay at startup is not critical.
"""
function start_audio!(eng::Engine; device = nothing, latency::Real = 0.15)
    eng.running && return eng
    if Threads.nthreads() < 2
        @warn L("Julia läuft mit nur einem Thread – Audio kann stottern. Starte mit `julia -t auto`.")
    end
    # Warm-up: precompile the render! paths so the JIT doesn't hit during playback
    warm = Engine(copy(eng.song), eng.kit)
    start_seq!(warm, [1], 1)
    wbuf = zeros(Float32, BLOCK, 2)
    for _ in 1:200
        render!(warm, wbuf)
    end
    kw = (samplerate = SR, latency = latency, frames_per_buffer = BLOCK)
    stream = device === nothing ? PortAudio.PortAudioStream(0, 2; kw...) :
                                  PortAudio.PortAudioStream(device, 0, 2; kw...)
    eng.running = true
    eng.task = Threads.@spawn begin
        buf = zeros(Float32, BLOCK, 2)
        try
            while eng.running
                lock(eng.lock) do
                    render!(eng, buf)
                end
                write(stream, buf)
            end
        catch e
            @error "Audio-Thread beendet" exception = (e, catch_backtrace())
        finally
            close(stream)
        end
    end
    return eng
end

function stop_audio!(eng::Engine)
    eng.running = false
    eng.task === nothing || wait(eng.task)
    eng.task = nothing
    return eng
end

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

"""
    render_song(song, kit; repeats, countin, click, loop, tail) -> Matrix{Float32}

Renders count-in + `repeats` × chain offline as a stereo matrix (samples × 2).

`loop = true`: seamless loop. No count-in, the length matches the chain exactly, and the
decay after the last bar (cymbals, reverb) is added to the beginning – so the file sounds
as if played through when looped endlessly, with no gap and no cut-off reverb.
"""
function render_song(song::Song, kit::Kit; repeats::Int = song.repeats, countin::Int = song.countin,
                     click::Bool = song.click, loop::Bool = song.loop, tail::Real = loop ? 4.0 : 2.0)
    loop && (countin = 0)
    s = copy(song)
    s.click = click
    eng = Engine(s, kit)
    seq = vcat(fill(0, countin), repeat(s.chain, max(repeats, 1)))
    start_seq!(eng, seq, 0)
    eng.next_step_at = 0.0
    blocks = Matrix{Float32}[]
    buf = zeros(Float32, BLOCK, 2)
    while !eng.finished
        render!(eng, buf)
        push!(blocks, copy(buf))
    end
    songlen = round(Int, eng.next_step_at)      # end of the last step
    for _ in 1:ceil(Int, tail * SR / BLOCK)
        render!(eng, buf)
        push!(blocks, copy(buf))
    end
    y = reduce(vcat, blocks)
    if loop
        n = clamp(songlen, 1, size(y, 1))
        out = y[1:n, :]
        @inbounds for k in n+1:size(y, 1), c in 1:2      # fold the decay cyclically onto the beginning
            out[mod1(k - n, n), c] += y[k, c]
        end
        return out
    end
    # Trim the decay after the song end once it is quieter than -70 dB
    last = findlast(>(10^(-70 / 20)), vec(maximum(abs, y; dims = 2)))
    n = clamp(max(songlen, something(last, 0)), 1, size(y, 1))
    return y[1:n, :]
end

const TRANSLIT = Dict('ä' => "ae", 'ö' => "oe", 'ü' => "ue", 'Ä' => "Ae", 'Ö' => "Oe", 'Ü' => "Ue", 'ß' => "ss")

"""
    ascii_filename(name) -> String

File name of ASCII characters only, as required e.g. by drum modules (Roland TD-27):
umlauts are spelled out (ä → ae, ß → ss), accents removed (é → e), all other
characters except letters, digits, spaces and `. _ - ( )` become `_`.
"""
function ascii_filename(name::AbstractString)
    s = join(get(TRANSLIT, c, string(c)) for c in name)
    s = Base.Unicode.normalize(s; stripmark = true)
    s = replace(s, r"[^A-Za-z0-9 ._()\-]" => "_")
    s = replace(s, r"_{2,}" => "_")
    return strip(s)
end

"""
    export_wav(path, song, kit; mono = song.mono, bits = 16, kw...) -> path

Writes the rendered song as a standard WAV (RIFF, PCM, 44.1 kHz, 16 bit like an audio CD):
stereo or, with `mono = true`, single-channel. The file name is converted to pure ASCII
with [`ascii_filename`](@ref); the path actually written is returned.
Other keywords as for [`render_song`](@ref).
"""
function export_wav(path::AbstractString, song::Song, kit::Kit; mono::Bool = song.mono, bits::Int = 16, kw...)
    path = joinpath(dirname(path), ascii_filename(basename(path)))
    s = copy(song)
    s.mono = mono
    y = render_song(s, kit; kw...)
    mono && (y = y[:, 1:1])                # both channels are identical
    mkpath(dirname(abspath(path)))
    bits in (16, 24) || error(L("bits muss 16 oder 24 sein"))
    q = 2^(bits - 1) - 1
    pcm = round.(Int32, clamp.(y, -1, 1) .* q)
    WAV.wavwrite(bits == 16 ? Int16.(pcm) : pcm, path; Fs = SR, nbits = bits,
                 compression = WAV.WAVE_FORMAT_PCM)
    return path
end


"""
    td27_name_warning(path) -> String

Hint for the Roland TD-27 song player: it shows only 16 characters of a file name correctly, and a
name ending in `_Click` is taken as the click track of another song. Returns `""` if all is fine.
"""
function td27_name_warning(path::AbstractString)
    base = splitext(basename(path))[1]
    msgs = String[]
    length(base) > 16 && push!(msgs, L("Name hat {1} Zeichen, das TD-27 zeigt nur 16", length(base)))
    endswith(lowercase(base), "_click") && push!(msgs, L("Name endet auf _Click – das TD-27 hält die Datei für eine Klick-Spur"))
    return join(msgs, "; ")
end

"Export length in seconds (without decay; with loop, without count-in)."
function song_seconds(song::Song; repeats::Int = song.repeats, countin::Int = song.loop ? 0 : song.countin)
    bar(p) = sum(step_samples(song, s, p) for s in 0:p.steps-1) / SR
    first = song.patterns[song.chain[1]]
    return countin * bar(first) + max(repeats, 1) * sum(bar(song.patterns[i]) for i in song.chain)
end
