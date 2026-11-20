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

"""
    Engine(song, kit)

Playback state of the GUI: the current [`Song`](@ref) and [`Kit`](@ref), the voices, effects and
transport. The audio callback calls it block by block; offline rendering ([`render_song`](@ref),
[`export_wav`](@ref)) uses its own engine, so scripts normally don't need to create one.
"""
mutable struct Engine
    song::Song
    kit::Kit
    kitgain::Float32                 # gain of the current kit (settings, see `kit_gain`)
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
    metro::Metronome
    pending::Vector{Tuple{Float64,Int,Int,Float32}}   # ornament strokes: (sample time, track, level, gain)
    humsched::Bool                   # hits of the next step are already in `humpend` (human timing)
    humpend::Vector{Tuple{Float64,Int,Int,Float32}}   # hits shifted by `song.human`, like `pending`
    player::Player                   # setup player (prepared songs), mixed in last
    seqout::SeqOut                   # MIDI output of the main window: hits go to a drum module
    clock::HitClock                  # timing log for MIDI recording (see src/midi.jl)
    hits::Union{Nothing,Vector{Tuple{Int,Int,Int,Float32}}}   # dry run: (sample, track, level, gain), no audio
    rt::Threads.Atomic{Int}          # realtime priority the audio thread runs with, 0 = normal
end

function Engine(song::Song, kit::Kit)
    fx = FXState()
    nos = Sample(Float32[])
    eng = Engine(song, kit, kit_gain(kit.name), [Voice() for _ in 1:NVOICES], fill(nos, NTRACKS), MersenneTwister(4711), fx,
                 [TrackFX() for _ in 1:NTRACKS], [zeros(Float32, BLOCK, 2) for _ in 1:NTRACKS], fill(false, NTRACKS),
                 click_sound(true), click_sound(false),
                 false, 0, 0.0, 0, Int[], 1, 0, 1, 1, false, false, false,
                 Threads.Atomic{Int}(-1), Threads.Atomic{Int}(1), Threads.Atomic{Int}(0),
                 Channel{Tuple{Int,Int}}(64), ReentrantLock(), false, nothing, Preview(), Metronome(),
                 sizehint!(Tuple{Float64,Int,Int,Float32}[], 64), false,
                 sizehint!(Tuple{Float64,Int,Int,Float32}[], NTRACKS), Player(), SeqOut(), HitClock(), nothing,
                 Threads.Atomic{Int}(0))
    apply_fx!(eng)
    return eng
end

"Applies the FX choice and mix from the song to the effect state (`render!` sets the echo delay from the tempo)."
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
                      track::Int, choke::Int; swap::Bool = false)
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
    p = clamp(swap ? -pan : pan, -1f0, 1f0)
    v.buf = swap ? smp.r : smp.l; v.bufr = swap ? smp.l : smp.r; v.pos = 0.0; v.rate = rate
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

"Gain of kit `name`: factor 0–2 from the settings table `kit_gain`, 1 if unset."
function kit_gain(name::AbstractString)
    v = get(get(load_settings(), "kit_gain", Dict{String,Any}()), name, 1.0)
    return v isa Real ? clamp(Float32(v), 0f0, 2f0) : 1f0
end

"Stores the gain of kit `name` in the settings file (applies to playback and export)."
function set_kit_gain!(name::AbstractString, g::Real)
    d = get(load_settings(), "kit_gain", Dict{String,Any}())
    d[String(name)] = round(Float64(g), digits = 2)
    save_setting!("kit_gain", d)
end

"Plays track `t` at velocity level `level` (1–3), scaled by `gain`. `seq=true` honors mute/solo."
function trigger!(eng::Engine, t::Int, level::Int; seq::Bool = true, gain::Float32 = 1f0)
    tp = eng.song.tracks[t]
    if seq
        tp.mute && return
        anysolo = any(x -> x.solo, eng.song.tracks)
        anysolo && !tp.solo && return
    end
    eng.hits === nothing || (push!(eng.hits, (eng.samplepos, t, level, gain)); return)
    if seq && seq_on(eng.seqout)              # MIDI output: the drum module plays it, not the kit
        seq_note!(eng.seqout, eng.samplepos, t, round(Int, MIDI_OUT_VEL[level] * gain * tp.vol * eng.seqout.gain))
        return
    end
    kit = eng.kit
    smp, g = pick_sample(eng.rng, kit.pools[t][level], eng.last[t])
    eng.last[t] = smp
    gain *= g * kit.gain[t] * tp.vol * eng.kitgain
    rate = 2.0^(tp.pitch / 12)
    start_voice!(eng, smp, gain, kit.pan[t] + tp.pan, rate, t, kit.choke[t]; swap = tp.swap)
    return
end

"""
Randomly picks `(recording, gain)` from the pool of a velocity level (see `level_pools`),
but not the same recording as last time – so fast repeats sound natural.
"""
function pick_sample(rng::AbstractRNG, pool::Vector{Tuple{Sample,Float32}}, prev::Sample)
    n = length(pool)
    k = rand(rng, 1:n)
    pool[k][1] === prev && n > 1 && (k = mod1(k + 1, n))   # no immediate repeat: next recording
    return pool[k]
end

function click!(eng::Engine, accent::Bool)
    eng.hits === nothing || (push!(eng.hits, (eng.samplepos, 0, accent ? 3 : 2, 1f0)); return)
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
    k = max(1, song.steps_per_beat ÷ 4)                    # steps per 16th
    return any(!iszero, @view p.grid[:, k+1:2k:p.steps]) ? 16 : 8
end

"""
Duration of step `s` (0-based) in samples, incl. swing. The bar length always stays the same:
with pattern `p`, an incomplete pair or group of three at the end of the bar is played straight.

Uniform meaning of `song.swing`: position of the off-beat note within its group
(50 % = middle/straight, 67 % = triplet, 75 % = dotted).

- 8th/16th/32nd grid: pairs (8th or 16th pair); the first half is stretched by `swing`.
- Triplet grid (3 or 6 per beat): groups of three; the third triplet sits at `swing`
  of the group, the middle one exactly in between. At 2/3 this gives exact triplets.
"""
function step_samples(song::Song, s::Int, p::Union{Pattern,Nothing} = nothing)
    spb = song.steps_per_beat
    base = 60.0 / pattern_bpm(song, p) / spb * SR             # own tempo of the pattern, else the song's
    sw = clamp(song.swing, 0.5, 0.8)
    if spb in (3, 6)
        p !== nothing && s >= p.steps - p.steps % 3 && return base   # incomplete last group
        g = 3base                                          # duration of a group of three
        return s % 3 == 2 ? (1 - sw) * g : sw * g / 2
    end
    (sw == 0.5 || !(spb in (2, 4, 8))) && return base
    # steps per swung note: an 8th is spb/2 steps, a 16th spb/4 (at least one step)
    n = max(1, swing_unit(song, p) == 16 ? spb ÷ 4 : spb ÷ 2)
    p !== nothing && s >= p.steps - p.steps % 2n && return base     # incomplete last pair
    return 2base * (s % 2n < n ? sw : 1 - sw)              # first note of the pair longer
end

resolve_pat(eng::Engine, p::Int) = seq_pattern(p, eng.edit_pat, length(eng.song.patterns))

function do_step!(eng::Engine)
    song = eng.song
    s = eng.step
    s == 0 && log_bar!(eng.clock, eng.next_step_at, eng.seqpos, eng.pat)
    log_step!(eng.clock, eng.next_step_at, s)
    if eng.pat == 0
        if s % song.steps_per_beat == 0
            click!(eng, s == 0)
        end
        p = countin_pattern(eng)
        steps = p.steps
    else
        p = song.patterns[eng.pat]
        steps = p.steps
    end
    if seq_on(eng.seqout) && s % song.steps_per_beat == 0 && s < steps   # MIDI clock of this beat
        e = min(s + song.steps_per_beat, steps)
        d = 0.0
        for j in s:e-1
            d += step_samples(song, j, p)
        end
        seq_beat!(eng.seqout, eng.next_step_at, d, 24 * (e - s) ÷ song.steps_per_beat)
    end
    if eng.pat != 0
        if s < steps
            for t in 1:NTRACKS
                lv = p.grid[t, s+1]
                lv > 0 || continue
                eng.humsched || trigger!(eng, t, Int(lv))     # else scheduled by `schedule_human!`
                o = p.orn[t, s+1]
                o in (ORN_DOUBLE, ORN_BUZZ) && add_roll!(eng, t, Int(lv), o, step_samples(song, s, p))
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
    schedule_graces!(eng)
    schedule_human!(eng)
    return
end

# Ornaments: timing of the extra strokes
# (distances and grace-note volume: `song.orn`, see OrnTuning)
const FLAM_GAIN = 0.9f0                # grace notes relative to `song.orn.grace`
const DRAG_GAIN = 1f0
const BUZZ_COUNT = 4:16                # strokes per step incl. the main stroke
const BUZZ_DECAY = 0.93                # gain factor from bounce to bounce

"Seconds before the main stroke at which the grace notes of a flam or drag come (earliest first)."
grace_gaps(o::OrnTuning, orn::UInt8) = orn == ORN_FLAM ? (o.flam_ms / 1000,) : (o.drag_ms / 500, o.drag_ms / 1000)

"Extra strokes of a double stroke or buzz roll within the current step (duration `d` samples)."
function add_roll!(eng::Engine, t::Int, lv::Int, o::UInt8, d::Float64)
    t0 = eng.next_step_at              # start of the step that is being played
    if o == ORN_DOUBLE                 # second stroke of the double on the half step
        push!(eng.pending, (t0 + d / 2, t, lv, 0.92f0))
    else                               # buzz: bounces getting softer
        n = clamp(round(Int, d / (eng.song.orn.buzz_ms / 1000 * SR)), first(BUZZ_COUNT), last(BUZZ_COUNT))
        for k in 1:n-1
            push!(eng.pending, (t0 + k * d / n, t, max(1, lv - 1), Float32(BUZZ_DECAY^k)))
        end
    end
end

"""
Grace notes (flam, drag) of the next step, placed just before it. They have to fit into the
time until that step: in fast grids the gaps shrink evenly (as when played fast).
"""
function schedule_graces!(eng::Engine)
    eng.pat > 0 || return              # count-in
    p = eng.song.patterns[eng.pat]
    s = eng.step + 1
    s <= p.steps || return
    T = eng.next_step_at
    room = max(T - eng.samplepos, 0.0)   # samples until the next step
    for t in 1:NTRACKS
        o = ornament(p, t, s)
        o in (ORN_FLAM, ORN_DRAG) || continue
        gaps = grace_gaps(eng.song.orn, o)
        f = min(1.0, 0.95room / (first(gaps) * SR))     # squeeze so that all grace notes fit
        g0 = Float32(eng.song.orn.grace) * (o == ORN_FLAM ? FLAM_GAIN : DRAG_GAIN)
        for g in gaps
            push!(eng.pending, (T - f * g * SR, t, 1, g0))
        end
    end
end

# Human (`song.human` 0…1): spread of level and timing per hit at 1, as standard deviation
const HUMAN_DB = 1.5                    # dB
const HUMAN_MS = 5.0                    # ms
const HUMAN_CUT = 2.0                   # at most this many standard deviations (±3 dB, ±10 ms)

"""
With `song.human > 0`: the hits of the next step go into `eng.humpend`, each with a random level
and time offset, so they can also come a little early (`early = false`: only late, for the first
step after the start, which an export would cut). `do_step!` then leaves them out.
"""
function schedule_human!(eng::Engine; early::Bool = true)
    eng.humsched = false
    h = eng.song.human
    (h > 0 && eng.pat > 0) || return
    p = eng.song.patterns[eng.pat]
    s = eng.step + 1
    s <= p.steps || return
    T = eng.next_step_at
    for t in 1:NTRACKS
        lv = p.grid[t, s]
        lv > 0 || continue
        dt = clamp(randn(eng.rng), -HUMAN_CUT, HUMAN_CUT) * h * HUMAN_MS / 1000 * SR
        db = clamp(randn(eng.rng), -HUMAN_CUT, HUMAN_CUT) * h * HUMAN_DB
        early || (dt = abs(dt))
        push!(eng.humpend, (max(T + dt, Float64(eng.samplepos)), t, Int(lv), Float32(10^(db / 20))))
    end
    eng.humsched = true
    return
end

const LEAD_IN = 0.1 * SR                # samples before step 1: room for its grace notes

"Starts playback of sequence `seq` (see field docs) right away."
function start_seq!(eng::Engine, seq::Vector{Int}, loop_from::Int)
    o = eng.seqout
    if o.started                                     # restart: the module's click starts again too
        seq_write!(o, Int32(0xfc), o.t0 + (eng.samplepos - o.pos0) * (1000 / SR))
        o.started = false; o.clk_left = 0
    end
    eng.seq = seq
    eng.loop_from = loop_from
    eng.seqpos = 1
    eng.pat = resolve_pat(eng, seq[1])
    eng.step = 0
    eng.next_step_at = eng.samplepos + LEAD_IN       # lead-in: room for grace notes of the first step
    eng.finished = false
    eng.playing = true
    eng.clock.nb = 0
    eng.clock.ns = 0
    empty!(eng.pending); empty!(eng.humpend)
    schedule_graces!(eng)
    schedule_human!(eng; early = false)
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
        empty!(eng.pending); empty!(eng.humpend)   # no leftover strokes after a stop
        for v in eng.voices
            v.active && v.fade == 0 && (v.fade = FADE_SAMPLES)
        end
    end
end

"""
Next sequencer event as `(time, k)`: `k > 0` is the ornament stroke `eng.pending[k]`, `k < 0`
the human-shifted hit `eng.humpend[-k]`, `k = 0` the next step. After the end of a sequence only
the remaining strokes count (time `Inf` once none are left), so the second stroke of a double or
a buzz roll on the last step still plays.
"""
function next_event(eng::Engine)
    tnext = eng.playing ? eng.next_step_at : Inf; k = 0
    for (j, ev) in enumerate(eng.pending)
        ev[1] < tnext && (tnext = ev[1]; k = j)
    end
    for (j, ev) in enumerate(eng.humpend)
        ev[1] < tnext && (tnext = ev[1]; k = -j)
    end
    return tnext, k
end

"Plays event `k` from [`next_event`](@ref): an ornament stroke, a human-shifted hit or the next step."
function fire_event!(eng::Engine, k::Int)
    if k != 0
        ev = k > 0 ? popat!(eng.pending, k) : popat!(eng.humpend, -k)
        trigger!(eng, ev[2], ev[3]; gain = ev[4])
    else
        do_step!(eng)
    end
    return
end

"Renders one block (frames × 2) – sample-accurate, steps may fall mid-block."
function render!(eng::Engine, out::Matrix{Float32})
    fill!(out, 0f0)
    N = size(out, 1)
    seq_block!(eng.seqout, eng.samplepos, N, eng.playing)
    while isready(eng.pads)
        t, lv = take!(eng.pads)
        t == 0 ? click!(eng, true) : trigger!(eng, t, lv; seq = false)
    end
    for t in 1:NTRACKS                       # track effects: prepare buses
        tp = eng.song.tracks[t]
        eng.fxon[t] = has_trackfx(tp)
        eng.fxon[t] || continue
        size(eng.bus[t], 1) == N || (eng.bus[t] = zeros(Float32, N, 2))
        fill!(eng.bus[t], 0f0)
        update_eq!(eng.trackfx[t], tp.eq_low, tp.eq_mid, tp.eq_midf, tp.eq_high)
    end
    i = 1
    o = eng.seqout
    while i <= N
        tnext, k = next_event(eng)                   # next step or ornament stroke
        o.clk_left > 0 && o.clk_next < tnext && (tnext = o.clk_next; k = typemin(Int))   # MIDI clock tick
        due = tnext - eng.samplepos
        if due <= 0
            k == typemin(Int) ? seq_tick!(o, eng.samplepos) : fire_event!(eng, k)
            continue
        end
        n = isfinite(due) ? min(N - i + 1, ceil(Int, due)) : N - i + 1
        mix_voices!(eng, out, i, n)
        eng.samplepos += n
        i += n
    end
    for t in 1:NTRACKS
        eng.fxon[t] && process_track!(eng.trackfx[t], eng.song.tracks[t], eng.bus[t], out, N)
    end
    m = Float32(eng.song.master)
    fx = eng.fx
    fx.echo.delay = echo_delay(eng.song.bpm, SR)     # echo on 8ths of the song tempo
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
    metro_active(eng.metro) && mix_metro!(eng.metro, out)
    if player_active(eng.player)
        mix_player!(eng.player, out)
    elseif eng.player.mout[] != 0           # MIDI clock keeps running: a manual start is timed at once
        midi_clock!(eng.player, size(out, 1))
    end
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

"Audio buffer in seconds: `audio_latency` in the settings file (0.02–0.5), default 0.08."
function audio_latency()
    v = get(load_settings(), "audio_latency", 0.08)
    return v isa Real ? clamp(Float64(v), 0.02, 0.5) : 0.08
end

# Realtime priority for the audio thread (Linux): `start_drum.sh --prio` sets DRUMMACHINE_RT to
# the priority the user may use (RLIMIT_RTPRIO); the audio task then runs with SCHED_FIFO.
const SCHED_OTHER, SCHED_FIFO = Cint(0), Cint(1)

"Requested realtime priority of the audio thread (environment DRUMMACHINE_RT), 0 = normal."
rt_priority() = (p = tryparse(Int, get(ENV, "DRUMMACHINE_RT", "")); p === nothing ? 0 : clamp(p, 0, 99))

"Scheduling of POSIX thread `thread`: `prio > 0` = SCHED_FIFO with that priority, 0 = normal. `true` if it worked."
function set_thread_sched!(thread::Culong, prio::Integer)
    Sys.islinux() || return false
    param = Ref{Cint}(prio)                          # struct sched_param { int sched_priority; }
    return ccall(:pthread_setschedparam, Cint, (Culong, Cint, Ref{Cint}), thread,
                 prio > 0 ? SCHED_FIFO : SCHED_OTHER, param) == 0
end
current_thread() = ccall(:pthread_self, Culong, ())

"""
Output buffer of `stream` for writing to the sound card directly from the audio task.
`write(stream, buf)` hands the block to a helper task of PortAudio.jl, which then calls the
blocking `Pa_WriteStream` on whatever thread it runs on; writing directly makes the audio thread
itself wait for the sound card, so its realtime priority applies where it matters.
`nothing` if this PortAudio.jl version is laid out differently (then `write` is used).
"""
function direct_sink(stream, frames::Int)
    try
        b = stream.sink_messenger.buffer
        return b.data isa Matrix{Float32} && size(b.data) == (2, frames) ? b : nothing
    catch
        return nothing
    end
end

"Writes `buf` (frames × 2) to the sound card: directly into `sink` if available, else via `write`."
function write_block!(stream, sink, buf::Matrix{Float32})
    if sink === nothing
        write(stream, buf)
    else
        d = sink.data
        @inbounds for k in axes(buf, 1), c in 1:2
            d[c, k] = buf[k, c]
        end
        PortAudio.write_buffer(sink, size(buf, 1))
    end
    return nothing
end

"Output latency of `stream` in s as reported by PortAudio, else the requested `fallback`."
function stream_latency(stream, fallback::Real)
    try
        p = PortAudio.LibPortAudio.Pa_GetStreamInfo(stream.pointer_to)
        if p != C_NULL
            l = unsafe_load(p).outputLatency
            l > 0 && return Float64(l)
        end
    catch e
        @debug "stream latency not available" exception = e
    end
    return Float64(fallback)
end

"""
    start_audio!(eng; device = nothing, latency = audio_latency())

Opens the audio device and starts the audio thread. `latency` (seconds) is the buffer to the
sound card: it is the delay of play/stop and metronome start, but too small a buffer lets garbage
collection pauses (Julia briefly halts all threads) cause dropouts.
"""
function start_audio!(eng::Engine; device = nothing, latency::Real = audio_latency())
    eng.running && return eng
    if Threads.nthreads() < 2
        @warn L("Julia läuft mit nur einem Thread – Audio kann stottern. Starte mit `julia -t auto`.")
    end
    # Warm-up: precompile the render! paths so the JIT doesn't hit during playback
    warm = Engine(copy(eng.song), eng.kit)
    start_seq!(warm, [1], 1)
    metro_start!(warm.metro)
    warm.seqout.sent = sizehint!(Tuple{Float64,Int32}[], 4096)   # MIDI output path, nothing sent
    wp = warm.player                         # player path with pause, beep, EQ and reverb
    wp.items = [zeros(Float32, 4BLOCK, 2)]; wp.cues = [BLOCK]; wp.delays = [0.01]; wp.beeps = [true]; wp.hall = 2
    wp.mframe = [[1, 2BLOCK]]; wp.mmsg = [Int32[0x99, 0x89]]; wp.mchans = [0x0200]   # MIDI entry (no output open)
    player_eq!(wp, 1, 0, 800, 0); player_start!(wp, 1; pause = true)
    wbuf = zeros(Float32, BLOCK, 2)
    for _ in 1:200
        render!(warm, wbuf)
    end
    kw = (samplerate = SR, latency = latency, frames_per_buffer = BLOCK)
    stream = device === nothing ? PortAudio.PortAudioStream(0, 2; kw...) :
                                  PortAudio.PortAudioStream(device, 0, 2; kw...)
    eng.running = true
    eng.clock.latency = stream_latency(stream, latency)    # what the sound card reports
    eng.metro.latency = eng.clock.latency                # metronome display delay: the same
    eng.player.mlat = 1000 * hit_delay(eng.clock.latency, 0)   # player MIDI: rendering to hearing, ms
    eng.seqout.mlat = eng.player.mlat
    logev("audio started"; device = something(device, "default"), latency_set = latency,
          latency_reported = round(eng.clock.latency; digits = 4), block = BLOCK, rate = SR)
    sink = direct_sink(stream, BLOCK)
    eng.task = Threads.@spawn begin
        buf = zeros(Float32, BLOCK, 2)
        rt = rt_priority(); rt_thread = Culong(0)
        try
            while eng.running
                if rt > 0 && (me = current_thread()) != rt_thread   # the task may move to another thread
                    if set_thread_sched!(me, rt)
                        rt_thread == 0 || set_thread_sched!(rt_thread, 0)   # the old thread back to normal
                        rt_thread == 0 && (@info L("Audio-Thread läuft mit Echtzeit-Priorität {1}.", rt); logev("audio realtime priority"; rt))
                        rt_thread = me
                        eng.rt[] = rt
                    else
                        @warn L("Echtzeit-Priorität für den Audio-Thread nicht erlaubt – normale Priorität.")
                        rt = 0; eng.rt[] = 0
                    end
                end
                lock(eng.lock) do
                    log_block!(eng.clock, time_ns(), eng.samplepos)
                    render!(eng, buf)
                end
                write_block!(stream, sink, buf)
            end
        catch e
            @error "Audio-Thread beendet" exception = (e, catch_backtrace())
        finally
            rt_thread == 0 || set_thread_sched!(rt_thread, 0)
            eng.rt[] = 0
            close(stream)
            # also after an error: show the transport stopped and let start_audio! open it again
            eng.running = false
            lock(eng.lock) do
                eng.playing = false
                eng.shown_step[] = -1
                empty!(eng.pending); empty!(eng.humpend)
            end
        end
    end
    return eng
end

function stop_audio!(eng::Engine)
    eng.task === nothing || logev("audio stopped")
    eng.running = false
    eng.task === nothing || wait(eng.task)
    eng.task = nothing
    return eng
end

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

"""
    start_offline!(eng; countin, repeats) -> eng

Starts count-in + `repeats` × chain once, for the WAV and MIDI export. As in live playback, step 1
comes after a lead-in of `LEAD_IN` samples, so the grace notes of a flam or drag on step 1 have
room; the exports cut it off again (see [`offline_start`](@ref)). Events then come from
[`next_event`](@ref) and [`fire_event!`](@ref), the same path as in `render!`.
"""
function start_offline!(eng::Engine; countin::Int, repeats::Int)
    eng.samplepos = 0
    start_seq!(eng, vcat(fill(0, countin), repeat(eng.song.chain, max(repeats, 1))), 0)
    return eng
end

"""
    export_pickup(eng) -> (samples, den)

Pickup before step 1 in an export without loop: `(0, 0)` without grace notes before step 1;
with a flam or drag on step 1 (no count-in) a 16th of the tempo of step 1, doubled until it
holds the grace notes (`den` = note value 16, 8, ...). WAV and MIDI file both start that long
before beat 1. Call it right after [`start_offline!`](@ref).
"""
function export_pickup(eng::Engine)
    lead = eng.next_step_at - minimum(first, eng.pending; init = eng.next_step_at)
    lead > 0 || return 0, 0
    len, den = 60 / pattern_bpm(eng.song, current_pattern(eng)) * SR / 4, 16
    while len < lead && den > 1
        len *= 2; den ÷= 2
    end
    return round(Int, len), den
end

"""
First sample of an export without loop (0-based engine time, negative if the pickup is longer
than the lead-in): step 1, or with a flam or drag on step 1 the start of the pickup bar
(see [`export_pickup`](@ref)). Call it right after [`start_offline!`](@ref).
"""
offline_start(eng::Engine) = round(Int, eng.next_step_at) - export_pickup(eng)[1]

"""
    render_song(song, kit; repeats, countin, click, loop, tail) -> Matrix{Float32}

Renders count-in + `repeats` × chain offline as a stereo matrix (samples × 2).

`loop = true`: seamless loop. No count-in, the length matches the chain exactly, and the
decay after the last bar (cymbals, reverb) is added to the beginning and the grace notes of a
flam or drag on step 1 go to the end – so the file sounds as if played through when looped
endlessly, with no gap and no cut-off reverb.

Without loop and without count-in, a flam or drag on step 1 starts the file with a pickup of a
16th before beat 1 (longer for a long flam or drag at a fast tempo), the same as in the MIDI
export (see `DrumMachine.export_pickup`).

`tail` is the decay in seconds after the last step (silence below -70 dB is trimmed); with the
Echo effect it is at least as long as the repeats need (one 8th per repeat).
"""
function render_song(song::Song, kit::Kit; repeats::Int = song.repeats, countin::Int = song.countin,
                     click::Bool = song.click, loop::Bool = song.loop,
                     tail::Real = max(loop ? 4.0 : 2.0, song.fx == "Echo" ? fx_tail("Echo", song.bpm, SR) / SR : 0.0))
    loop && (countin = 0)
    s = copy(song)
    s.click = click
    eng = Engine(s, kit)
    start_offline!(eng; countin, repeats)
    L = round(Int, eng.next_step_at)            # step 1 (after the lead-in)
    a = loop ? L : offline_start(eng)           # first sample of the file
    blocks = Matrix{Float32}[]
    buf = zeros(Float32, BLOCK, 2)
    while !eng.finished
        render!(eng, buf)
        push!(blocks, copy(buf))
    end
    songend = round(Int, eng.next_step_at)      # end of the last step
    for _ in 1:ceil(Int, tail * SR / BLOCK)     # decay; also plays the last ornament strokes
        render!(eng, buf)
        push!(blocks, copy(buf))
    end
    y = reduce(vcat, blocks)
    if loop
        # sample k of y is time k-1, i.e. loop position k-1-L: the decay after the end goes to the
        # beginning, the grace notes of step 1 in the lead-in to the end
        n = clamp(songend - L, 1, size(y, 1))
        out = zeros(Float32, n, 2)
        @inbounds for k in 1:size(y, 1), c in 1:2
            out[mod1(k - L, n), c] += y[k, c]
        end
        return out
    end
    # Trim the decay after the song end once it is quieter than -70 dB
    last = findlast(>(10^(-70 / 20)), vec(maximum(abs, y; dims = 2)))
    n = clamp(max(songend, something(last, 0)), max(a + 1, 1), size(y, 1))
    a >= 0 && return y[a+1:n, :]
    return vcat(zeros(Float32, -a, 2), y[1:n, :])     # pickup longer than the lead-in
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
    logev("WAV exported"; path, song = song.name, kit = kit.name, seconds = round(size(y, 1) / SR; digits = 1), bits)
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
