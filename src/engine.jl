# Audio-Engine: sample-genauer Sequencer + Voice-Mixer. Dieselbe `render!`-Funktion wird
# für die Live-Wiedergabe (PortAudio) und den WAV-Export verwendet.

import PortAudio
using Random: MersenneTwister, AbstractRNG

const BLOCK = 512
const NVOICES = 64
const FADE_SAMPLES = round(Int, 0.008 * SR)     # Ausblendzeit beim Abwürgen (Hi-Hat-Choke)

# Velocity-Stufe (Ghost, normal, Akzent) -> Anteil der Kit-Layer (leise → laut) und Pegel
const LEVEL_RANGE = ((0.0, 0.4), (0.4, 0.8), (0.8, 1.0))
const LEVEL_GAIN = (0.5f0, 0.8f0, 1.0f0)

"Layer-Indizes (1…nl) für Velocity-Stufe `level`; bei 5 Layern: 1–2, 3–4, 5."
function level_layers(level::Int, nl::Int)
    f0, f1 = LEVEL_RANGE[level]
    lo = min(nl, floor(Int, f0 * nl) + 1)
    hi = clamp(round(Int, f1 * nl), lo, nl)
    return lo:hi
end

mutable struct Voice
    buf::Vector{Float32}
    bufr::Vector{Float32}  # rechter Kanal (=== buf bei Mono-Samples)
    pos::Float64
    rate::Float64
    gl::Float32
    gr::Float32
    track::Int
    choke::Int
    fade::Int            # > 0: wird ausgeblendet (verbleibende Samples)
    active::Bool
end
Voice() = (b = Float32[]; Voice(b, b, 0.0, 1.0, 0f0, 0f0, 0, 0, 0, false))

mutable struct Engine
    song::Song
    kit::Kit
    voices::Vector{Voice}
    last::Vector{Sample}             # zuletzt gespieltes Sample je Spur (keine direkte Wiederholung)
    rng::MersenneTwister             # geseedet → Exporte sind reproduzierbar
    fx::FXState
    click_hi::Sample
    click_lo::Sample
    # Transport
    playing::Bool
    samplepos::Int
    next_step_at::Float64
    step::Int                        # nächster Step (0-basiert)
    seq::Vector{Int}                 # Takte: 0 = Einzähler, -1 = aktuelles Edit-Pattern, sonst Pattern-Index
    seqpos::Int
    loop_from::Int                   # 0 = am Ende stoppen
    pat::Int                         # spielendes Pattern (0 = Einzähler)
    edit_pat::Int
    songmode::Bool
    live_countin::Bool
    finished::Bool
    # Anzeige (vom GUI gelesen)
    shown_step::Threads.Atomic{Int}
    shown_pat::Threads.Atomic{Int}
    shown_seqpos::Threads.Atomic{Int}
    # Vorhören von Spuren (vom GUI befüllt)
    pads::Channel{Tuple{Int,Int}}
    lock::ReentrantLock
    running::Bool
    task::Union{Task,Nothing}
end

function Engine(song::Song, kit::Kit)
    fx = FXState()
    nos = Sample(Float32[])
    eng = Engine(song, kit, [Voice() for _ in 1:NVOICES], fill(nos, NTRACKS), MersenneTwister(4711), fx,
                 click_sound(true), click_sound(false),
                 false, 0, 0.0, 0, Int[], 1, 0, 1, 1, false, false, false,
                 Threads.Atomic{Int}(-1), Threads.Atomic{Int}(1), Threads.Atomic{Int}(0),
                 Channel{Tuple{Int,Int}}(64), ReentrantLock(), false, nothing)
    apply_fx!(eng)
    return eng
end

"Übernimmt FX-Auswahl und Mix aus dem Song in den Effektzustand."
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
    if choke > 0                      # gleiche Choke-Gruppe ausblenden
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
    if v === nothing                  # ältestes Voice stehlen
        v = eng.voices[argmax(w.pos for w in eng.voices)]
    end
    p = clamp(pan, -1f0, 1f0)
    v.buf = smp.l; v.bufr = smp.r; v.pos = 0.0; v.rate = rate
    if isstereo(smp)          # Stereo-Sample: Balance, Mitte = unverändert
        v.gl = gain * min(1f0, 1f0 - p)
        v.gr = gain * min(1f0, 1f0 + p)
    else                      # Mono-Sample: Equal-Power-Panorama
        θ = (p + 1f0) * Float32(π) / 4
        v.gl = gain * cos(θ)
        v.gr = gain * sin(θ)
    end
    v.track = track; v.choke = choke; v.fade = 0; v.active = true
    return v
end

"Spielt Spur `t` mit Velocity-Stufe `level` (1–3). `seq=true` berücksichtigt Mute/Solo."
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
    gain = LEVEL_GAIN[level] * kit.gain[t] * tp.vol
    rate = 2.0^(tp.pitch / 12)
    start_voice!(eng, smp, gain, kit.pan[t] + tp.pan, rate, t, kit.choke[t])
    return
end

"""
Wählt zufällig eine Aufnahme aus den Layern der Velocity-Stufe (alle Round-Robins),
aber nicht dieselbe wie zuletzt – so klingen schnelle Wiederholungen natürlich.
"""
function pick_sample(rng::AbstractRNG, layers::Vector{Vector{Sample}}, level::Int, prev::Sample)
    r = level_layers(level, length(layers))
    n = sum(length(layers[l]) for l in r)
    k = rand(rng, 1:n)
    s = nth_sample(layers, r, k)
    if s === prev && n > 1                 # keine direkte Wiederholung: nächste Aufnahme
        s = nth_sample(layers, r, mod1(k + 1, n))
    end
    return s
end

function nth_sample(layers, r, k)
    for l in r
        k <= length(layers[l]) && return layers[l][k]
        k -= length(layers[l])
    end
    error("Index außerhalb der Layer")
end

function click!(eng::Engine, accent::Bool)
    start_voice!(eng, accent ? eng.click_hi : eng.click_lo, accent ? 0.7f0 : 0.5f0, 0f0, 1.0, 0, 0)
end

@inline function mix_voices!(eng::Engine, out::Matrix{Float32}, i0::Int, n::Int)
    @inbounds for v in eng.voices
        v.active || continue
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

"Erstes echtes Pattern der Sequenz, bestimmt die Länge des Einzählers."
function countin_pattern(eng::Engine)
    for p in eng.seq
        p > 0 && return eng.song.patterns[p]
        p == -1 && return eng.song.patterns[eng.edit_pat]
    end
    return eng.song.patterns[1]
end

"""
Swing-Basis für Pattern `p`: 8 oder 16. Bei Auto (0) wird auf 16tel geswingt, sobald im
Pattern Schläge auf „e“ oder „a“ liegen, sonst auf 8tel.
"""
function swing_unit(song::Song, p::Union{Pattern,Nothing})
    song.swing_on != 0 && return song.swing_on
    p === nothing && return 16
    return any(!iszero, @view p.grid[:, 2:2:p.steps]) ? 16 : 8
end

"""
Dauer von Step `s` (0-basiert) in Samples, inkl. Swing. Die Taktlänge bleibt immer gleich.

Einheitliche Bedeutung von `song.swing`: Lage der Off-Beat-Note innerhalb ihrer Gruppe
(50 % = Mitte/gerade, 67 % = Triole, 75 % = punktiert).

- 8tel-/16tel-Raster: Paare (8tel- bzw. 16tel-Paar); die erste Hälfte wird um `swing` gedehnt.
- Triolen-Raster (3 bzw. 6 pro Schlag): Dreiergruppen; die dritte Triole liegt bei `swing`
  der Gruppe, die mittlere genau dazwischen. Bei 2/3 ergeben sich exakte Triolen.
"""
function step_samples(song::Song, s::Int, p::Union{Pattern,Nothing} = nothing)
    spb = song.steps_per_beat
    base = 60.0 / song.bpm / spb * SR
    sw = clamp(song.swing, 0.5, 0.8)
    if spb in (3, 6)
        g = 3base                                          # Dauer einer Dreiergruppe
        return s % 3 == 2 ? (1 - sw) * g : sw * g / 2
    end
    (sw == 0.5 || !(spb in (2, 4))) && return base
    if spb == 2 || swing_unit(song, p) == 16
        return 2base * (iseven(s) ? sw : 1 - sw)          # Paare aus einzelnen Steps
    end
    return 2base * (s % 4 < 2 ? sw : 1 - sw)               # 16tel-Raster, Swing auf 8tel
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

"Startet die Wiedergabe mit Sequenz `seq` (siehe Feld-Doku) ab sofort."
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

"Live: Pattern-Modus (aktuelles Edit-Pattern in Schleife) oder Song-Modus (Kette in Schleife)."
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

"Rendert einen Block (frames × 2) – sample-genau, Steps können mitten im Block liegen."
function render!(eng::Engine, out::Matrix{Float32})
    fill!(out, 0f0)
    while isready(eng.pads)
        t, lv = take!(eng.pads)
        t == 0 ? click!(eng, true) : trigger!(eng, t, lv; seq = false)
    end
    N = size(out, 1)
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
    m = Float32(eng.song.master)
    fx = eng.fx
    @inbounds for k in 1:N
        l, r = process(fx, out[k, 1], out[k, 2])
        if eng.song.mono                    # Summe L+R auf beide Kanäle (Pegel ~ wie Stereo-Mitte)
            l = r = (l + r) * 0.7071f0
        end
        out[k, 1] = tanh(l * m)
        out[k, 2] = tanh(r * m)
    end
    return out
end

# ---------------------------------------------------------------------------
# Live-Audio
# ---------------------------------------------------------------------------

"""
    start_audio!(eng; device = nothing, latency = 0.15)

Öffnet das Audiogerät und startet den Audio-Thread. `latency` (Sekunden) ist der Puffer zur
Soundkarte: Großzügig gewählt, damit Pausen der Garbage Collection (Julia hält dabei alle
Threads kurz an, GLMakie erzeugt beim Zeichnen viel Müll) nicht zu Aussetzern führen.
Für ein Übungstool ist die Verzögerung beim Start unkritisch.
"""
function start_audio!(eng::Engine; device = nothing, latency::Real = 0.15)
    eng.running && return eng
    if Threads.nthreads() < 2
        @warn "Julia läuft mit nur einem Thread – Audio kann stottern. Starte mit `julia -t auto`."
    end
    # Aufwärmen: render!-Pfade vorab kompilieren, damit der JIT nicht in die Wiedergabe fällt
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
    render_song(song, kit; repeats, countin, click, tail=2.0) -> Matrix{Float32}

Rendert Einzähler + `repeats` × Kette offline als Stereo-Matrix (Samples × 2).
"""
function render_song(song::Song, kit::Kit; repeats::Int = song.repeats, countin::Int = song.countin,
                     click::Bool = song.click, tail::Real = 2.0)
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
    songlen = round(Int, eng.next_step_at)      # Ende des letzten Steps
    for _ in 1:ceil(Int, tail * SR / BLOCK)
        render!(eng, buf)
        push!(blocks, copy(buf))
    end
    y = reduce(vcat, blocks)
    # Ausklingen nach Songende kürzen, sobald es leiser als -70 dB ist
    last = findlast(>(10^(-70 / 20)), vec(maximum(abs, y; dims = 2)))
    n = clamp(max(songlen, something(last, 0)), 1, size(y, 1))
    return y[1:n, :]
end

"""
    export_wav(path, song, kit; mono = song.mono, bits = 16, kw...) -> path

Schreibt den gerenderten Song als WAV (44,1 kHz): Stereo oder, bei `mono = true`, einkanalig.
Weitere Schlüsselwörter wie bei [`render_song`](@ref).
"""
function export_wav(path::AbstractString, song::Song, kit::Kit; mono::Bool = song.mono, bits::Int = 16, kw...)
    s = copy(song)
    s.mono = mono
    y = render_song(s, kit; kw...)
    mono && (y = y[:, 1:1])                # beide Kanäle sind identisch
    mkpath(dirname(abspath(path)))
    bits in (16, 24) || error("bits muss 16 oder 24 sein")
    q = 2^(bits - 1) - 1
    pcm = round.(Int32, clamp.(y, -1, 1) .* q)
    WAV.wavwrite(bits == 16 ? Int16.(pcm) : pcm, path; Fs = SR, nbits = bits,
                 compression = WAV.WAVE_FORMAT_PCM)
    return path
end

"Länge des Exports in Sekunden (ohne Ausklingen)."
function song_seconds(song::Song; repeats::Int = song.repeats, countin::Int = song.countin)
    bar(p) = sum(step_samples(song, s, p) for s in 0:p.steps-1) / SR
    first = song.patterns[song.chain[1]]
    return countin * bar(first) + max(repeats, 1) * sum(bar(song.patterns[i]) for i in song.chain)
end
