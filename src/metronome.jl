# Metronome: its own click voices, mixed after master effect and limiter (like the editor
# preview), so it sounds the same whatever the song settings are. It runs independently of song
# playback. Tempo changes take effect at once, all other settings at the next bar.

"Time signatures: (label, pulses per bar, pulse length in quarter notes, accent groups)."
const METER_OPTS = [
    ("1/4", 1, 1.0, [1]), ("2/4", 2, 1.0, [2]), ("3/4", 3, 1.0, [3]), ("4/4", 4, 1.0, [4]),
    ("5/4 (3+2)", 5, 1.0, [3, 2]), ("5/4 (2+3)", 5, 1.0, [2, 3]), ("6/4 (3+3)", 6, 1.0, [3, 3]),
    ("7/4 (4+3)", 7, 1.0, [4, 3]),
    ("3/8", 3, 0.5, [3]), ("5/8 (3+2)", 5, 0.5, [3, 2]), ("6/8 (3+3)", 6, 0.5, [3, 3]),
    ("7/8 (2+2+3)", 7, 0.5, [2, 2, 3]), ("7/8 (3+2+2)", 7, 0.5, [3, 2, 2]),
    ("9/8 (3+3+3)", 9, 0.5, [3, 3, 3]), ("12/8 (3+3+3+3)", 12, 0.5, [3, 3, 3, 3]),
]

"Subdivision of each pulse: (label, click positions within the pulse, 0 = the pulse itself)."
const SUBDIV_OPTS = [
    ("keine", [0.0]),   # i18n-ok: translated where displayed
    ("2 pro Schlag (Achtel)", [0.0, 1 / 2]),   # i18n-ok: translated where displayed
    ("3 pro Schlag (Triolen)", [0.0, 1 / 3, 2 / 3]),   # i18n-ok: translated where displayed
    ("4 pro Schlag (16tel)", [0.0, 1 / 4, 1 / 2, 3 / 4]),   # i18n-ok: translated where displayed
    ("5 pro Schlag", collect(0:4) ./ 5),   # i18n-ok: translated where displayed
    ("6 pro Schlag (Sextolen)", collect(0:5) ./ 6),   # i18n-ok: translated where displayed
    ("Swing (1. + 3. Triole)", [0.0, 2 / 3]),
    ("Punktiert (1. + 4. 16tel)", [0.0, 3 / 4]),
]

"Which pulses sound. The subdivision only applies to the first two."
const ACCENT_OPTS = ["Akzent auf der 1", "Ohne Akzent", "Nur 2 und 4", "Nur Offbeats (+)", "Nur die 1"]   # i18n-ok: translated where displayed

const SOUND_OPTS = ["Klick", "Beep", "Woodblock", "Cowbell", "Claves", "Sticks", "Kit: Side Stick",
                    "Kit: Ride", "Kit: Hi-Hat"]

"Kit sounds: (track for the accent, track for beat and subdivision)."
const KIT_CLICKS = Dict(7 => ("Rim", "Rim"), 8 => ("RideBell", "Ride"), 9 => ("HiHat", "HiHat"))

"Loudest, middle and softest layer of `id` in `kit` (first round-robin each)."
function kit_layers(kit::Kit, id::AbstractString)
    ls = kit.layers[track_index(id)]
    return first(ls[end]), first(ls[cld(length(ls), 2)]), first(ls[1])
end

"Click sounds for `style` (index into `SOUND_OPTS`): (accent, beat, subdivision)."
function metro_sounds(style::Int, kit::Union{Kit,Nothing} = nothing)
    tone(f, dec, len = 0.08; drop = 0.0) = begin
        n = _n(len); t = _t(n)
        ph = cumsum(2π .* f .* (1 .+ drop .* exp.(-t ./ 0.004)) ./ SR)
        sin.(ph) .* exp.(-t ./ dec)
    end
    noise(n, seed) = (rng = MersenneTwister(seed); 2 .* rand(rng, n) .- 1)
    mk(x) = Sample(finish(x; peak = 0.8))
    if style == 2                                        # digital beep (soft square)
        beep(f) = (n = _n(0.06); t = _t(n);
                   tanh.(3 .* sin.(2π * f .* t)) .* min.(1, (_n(0.06) .- (0:n-1)) ./ _n(0.01)))
        return mk(beep(1760.0)), mk(beep(1320.0)), mk(beep(1320.0) .* 0.6)
    elseif style == 3                                    # woodblock: short resonant knock
        wb(f) = (x = tone(f, 0.02, 0.1; drop = 0.15); n = length(x);
                 x .+ 0.4 .* bandpass!(noise(n, 7), f, 4.0) .* exp.(-_t(n) ./ 0.004))
        return mk(wb(1250.0)), mk(wb(900.0)), mk(wb(900.0))
    elseif style == 4                                    # cowbell: two square waves, band-passed
        cb(f) = (n = _n(0.35); t = _t(n);
                 x = sign.(sin.(2π * f .* t)) .+ sign.(sin.(2π * 1.48f .* t));
                 bandpass!(x, 1.6f, 1.2) .* (0.4 .* exp.(-t ./ 0.012) .+ 0.6 .* exp.(-t ./ 0.12)))
        return mk(cb(700.0)), mk(cb(560.0)), mk(cb(560.0))
    elseif style == 5                                    # claves: bright short ping
        return mk(tone(2600.0, 0.025)), mk(tone(2100.0, 0.025)), mk(tone(2100.0, 0.015))
    elseif style == 6                                    # sticks clicked together
        st(f) = (n = _n(0.05); t = _t(n);
                 bandpass!(noise(n, 11), f, 1.5) .* exp.(-t ./ 0.006) .+ 0.5 .* tone(f * 0.6, 0.01, 0.05))
        return mk(st(4200.0)), mk(st(3000.0)), mk(st(3000.0))
    elseif haskey(KIT_CLICKS, style) && kit !== nothing  # instruments of the current kit
        acc, beat = KIT_CLICKS[style]
        _, mid, soft = kit_layers(kit, beat)
        return first(kit_layers(kit, acc)), mid, soft
    end
    return click_sound(true), click_sound(false), click_sound(false)    # classic click
end

"One playing click."
mutable struct MVoice
    buf::Vector{Float32}
    bufr::Vector{Float32}
    pos::Int
    gain::Float32
    active::Bool
end
MVoice() = (b = Float32[]; MVoice(b, b, 1, 0f0, false))

"""
Metronome settings and state. Settings are written by the GUI (under the engine lock), the state
is advanced by `mix_metro!` in the audio thread.
"""
mutable struct Metronome
    on::Bool
    bpm::Float64                     # quarter notes per minute
    meter::Int                       # index into METER_OPTS
    subdiv::Int                      # index into SUBDIV_OPTS
    accent::Int                      # index into ACCENT_OPTS
    sound::Int                       # index into SOUND_OPTS
    vol::Float32
    subvol::Float32
    gap_play::Int                    # gap training: play n bars, then mute m bars (m = 0: off)
    gap_mute::Int
    trainer_step::Int                # tempo trainer: +step BPM every `trainer_bars` bars up to max
    trainer_bars::Int
    trainer_max::Int
    sounds::NTuple{3,Sample}         # accent, beat, subdivision
    # state
    events::Vector{Tuple{Float64,Int}}   # (time in quarters within the bar, level 0 = sub … 3 = accent)
    ev::Int
    pos::Float64                     # position in the bar in quarter notes
    barlen::Float64
    bar::Int                         # bars since start (0-based)
    muted::Bool
    voices::Vector{MVoice}
    latency::Float64                 # output latency in s (display delay)
    shown_pos::Threads.Atomic{Float64}
    shown_bar::Threads.Atomic{Int}
end

Metronome() = Metronome(false, 100.0, 4, 1, 1, 1, 0.8f0, 0.5f0, 0, 0, 0, 4, 160, metro_sounds(1),
                        Tuple{Float64,Int}[], 1, 0.0, 4.0, 0, false, [MVoice() for _ in 1:16], 0.0,
                        Threads.Atomic{Float64}(0.0), Threads.Atomic{Int}(-1))

"Pulse length (quarters), number of pulses and accent groups of the current meter."
metro_meter(m::Metronome) = (o = METER_OPTS[clamp(m.meter, 1, length(METER_OPTS))]; (o[3], o[2], o[4]))

"Clicks of one bar for the current settings, sorted by time."
function metro_events(m::Metronome)
    plen, np, groups = metro_meter(m)
    starts = cumsum([1; groups[1:end-1]])           # first pulse of each group
    subs = SUBDIV_OPTS[clamp(m.subdiv, 1, length(SUBDIV_OPTS))][2]
    mode = m.accent
    ev = Tuple{Float64,Int}[]
    for p in 1:np
        t0 = (p - 1) * plen
        if mode == 4                                 # offbeats only
            push!(ev, (t0 + plen / 2, 1)); continue
        end
        lvl = mode == 1 ? (p == 1 ? 3 : p in starts ? 2 : 1) :
              mode == 2 ? 1 :
              mode == 3 ? (iseven(p) ? 1 : 0) :
              (p == 1 ? 3 : 0)                       # mode 5: the one only
        lvl > 0 && push!(ev, (t0, lvl))
        if mode <= 2
            for s in subs[2:end]
                push!(ev, (t0 + s * plen, 0))
            end
        end
    end
    sort!(ev; by = first)
    return ev
end

"Gap training: is bar `b` (0-based) a silent bar?"
metro_muted(m::Metronome, b::Integer) =
    m.gap_mute > 0 && m.gap_play > 0 && mod(b, m.gap_play + m.gap_mute) >= m.gap_play

"Rebuilds the bar from the settings (at the start of each bar)."
function metro_bar!(m::Metronome)
    plen, np, _ = metro_meter(m)
    m.barlen = plen * np
    m.events = metro_events(m)
    m.ev = 1
    m.muted = metro_muted(m, m.bar)
    return m
end

"Starts the metronome on the one."
function metro_start!(m::Metronome)
    m.bar = 0; m.pos = 0.0
    metro_bar!(m)
    m.on = true
    return m
end

metro_stop!(m::Metronome) = (m.on = false; m.shown_bar[] = -1; m)

function metro_click!(m::Metronome, level::Int)
    smp = level == 3 ? m.sounds[1] : level == 0 ? m.sounds[3] : m.sounds[2]
    g = m.vol * (level == 3 ? 1f0 : level == 2 ? 0.85f0 : level == 1 ? 0.7f0 : 0.55f0 * m.subvol)
    g > 0 || return
    v = nothing
    for w in m.voices
        w.active || (v = w; break)
    end
    v === nothing && (v = m.voices[argmax(w.pos for w in m.voices)])
    v.buf = smp.l; v.bufr = smp.r; v.pos = 1; v.gain = g; v.active = true
    return
end

"Adds the metronome to `out` (frames × 2), sample-accurately."
function mix_metro!(m::Metronome, out::Matrix{Float32})
    dq = m.bpm / (60 * SR)                           # quarter notes per sample
    @inbounds for k in 1:size(out, 1)
        if m.on
            while m.ev <= length(m.events) && m.events[m.ev][1] <= m.pos
                m.muted || metro_click!(m, m.events[m.ev][2])
                m.ev += 1
            end
            m.pos += dq
            if m.pos >= m.barlen
                m.pos -= m.barlen
                m.bar += 1
                if m.trainer_step > 0 && m.trainer_bars > 0 && m.bar % m.trainer_bars == 0
                    m.bpm = min(m.bpm + m.trainer_step, max(m.trainer_max, m.bpm))
                    dq = m.bpm / (60 * SR)
                end
                metro_bar!(m)
            end
        end
        for v in m.voices
            v.active || continue
            if v.pos > length(v.buf)
                v.active = false; continue
            end
            out[k, 1] += v.buf[v.pos] * v.gain
            out[k, 2] += v.bufr[v.pos] * v.gain
            v.pos += 1
        end
    end
    if m.on
        m.shown_pos[] = m.pos; m.shown_bar[] = m.bar
    end
    return out
end

"True while clicks are playing or ringing out."
metro_active(m::Metronome) = m.on || any(v -> v.active, m.voices)

"Settings as a Dict for the settings file."
metro_settings(m::Metronome) = Dict{String,Any}(
    "bpm" => m.bpm, "meter" => METER_OPTS[m.meter][1], "subdiv" => m.subdiv, "accent" => m.accent,
    "sound" => SOUND_OPTS[m.sound], "vol" => Float64(m.vol), "subvol" => Float64(m.subvol),
    "gap_play" => m.gap_play, "gap_mute" => m.gap_mute,
    "trainer_step" => m.trainer_step, "trainer_bars" => m.trainer_bars, "trainer_max" => m.trainer_max)

"Applies stored settings (unknown or invalid values are ignored)."
function metro_apply_settings!(m::Metronome, d::AbstractDict, kit = nothing)
    num(k, lo, hi, def) = (v = get(d, k, def); v isa Real ? clamp(v, lo, hi) : def)
    m.bpm = Float64(num("bpm", 30, 400, m.bpm))
    k = findfirst(o -> o[1] == get(d, "meter", ""), METER_OPTS); k === nothing || (m.meter = k)
    m.subdiv = Int(num("subdiv", 1, length(SUBDIV_OPTS), m.subdiv))
    m.accent = Int(num("accent", 1, length(ACCENT_OPTS), m.accent))
    k = findfirst(==(get(d, "sound", "")), SOUND_OPTS); k === nothing || (m.sound = k)
    m.vol = Float32(num("vol", 0, 1, m.vol)); m.subvol = Float32(num("subvol", 0, 1, m.subvol))
    m.gap_play = Int(num("gap_play", 0, 64, m.gap_play)); m.gap_mute = Int(num("gap_mute", 0, 64, m.gap_mute))
    m.trainer_step = Int(num("trainer_step", 0, 50, m.trainer_step))
    m.trainer_bars = Int(num("trainer_bars", 1, 64, m.trainer_bars))
    m.trainer_max = Int(num("trainer_max", 30, 400, m.trainer_max))
    m.sounds = metro_sounds(m.sound, kit)
    return m
end
