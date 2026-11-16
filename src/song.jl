# Song model: patterns (grid of tracks × steps), chain, track settings, presets, TOML I/O.

const MAXSTEPS = 32

# Grid values: 0 = off, 1 = ghost note (soft), 2 = normal, 3 = accent
const LEVEL_CHARS = ('.', 'o', 'x', 'X')
const LEVEL_NAMES = ("aus", "Ghost", "normal", "Akzent")

# Ornament of a hit: 0 = none, 1 = double stroke (two 32nds in the step), 2 = buzz roll,
# 3 = flam (one grace note just before), 4 = drag/ruff (two grace notes just before)
const ORN_CHARS = ('.', '2', 'z', 'f', 'r')
const ORN_NAMES = ("keine", "Doppelschlag", "Buzz-Roll", "Flam", "Drag")   # i18n-ok: shown via Ls()
const ORN_DOUBLE, ORN_BUZZ, ORN_FLAM, ORN_DRAG = 0x01, 0x02, 0x03, 0x04

mutable struct Pattern
    steps::Int
    grid::Matrix{UInt8}          # NTRACKS × MAXSTEPS
    orn::Matrix{UInt8}           # NTRACKS × MAXSTEPS, ornament (only counts where grid > 0)
    bpm::Float64                 # own tempo of this pattern, 0 = song tempo
end
Pattern(steps::Int, grid::Matrix{UInt8}, orn::Matrix{UInt8}) = Pattern(steps, grid, orn, 0.0)
Pattern(steps::Int, grid::Matrix{UInt8}) = Pattern(steps, grid, zeros(UInt8, NTRACKS, MAXSTEPS))
Pattern(steps::Int = 16) = Pattern(steps, zeros(UInt8, NTRACKS, MAXSTEPS))
Base.copy(p::Pattern) = Pattern(p.steps, copy(p.grid), copy(p.orn), p.bpm)

const BPM_RANGE = (30.0, 400.0)

# Per-track modulation effects and their defaults (rate in Hz, depth 0…1, feedback 0…0.9)
const MOD_NAMES = ["Aus", "Chorus", "Flanger"]
const MOD_DEFAULTS = Dict("Chorus" => (mix = 0.8, rate = 0.8, depth = 0.8, fb = 0.0),
                          "Flanger" => (mix = 1.0, rate = 0.3, depth = 0.9, fb = 0.75))
const EQ_MIDF_DEFAULT = 800.0

mutable struct TrackParams
    vol::Float32                 # 0 … 1.5
    pan::Float32                 # offset from the kit panning, -1 … 1
    pitch::Float32               # semitones
    mute::Bool
    solo::Bool
    # 3-band EQ in dB (-12 … +12): low shelf 120 Hz, mid bell at eq_midf, high shelf 5 kHz
    eq_low::Float32
    eq_mid::Float32
    eq_midf::Float32             # Hz, 200 … 6000
    eq_high::Float32
    # Modulation: index into MOD_NAMES
    mod::Int
    mod_mix::Float32             # 0 … 1
    mod_rate::Float32            # Hz
    mod_depth::Float32           # 0 … 1
    mod_fb::Float32              # 0 … 0.9
    swap::Bool                   # mirror the track left <-> right (stereo samples: swap channels)
end
function TrackParams(; vol = 1, pan = 0, pitch = 0, mute = false, solo = false,
                     eq_low = 0, eq_mid = 0, eq_midf = EQ_MIDF_DEFAULT, eq_high = 0,
                     mod = 1, mod_mix = 0.5, mod_rate = 0.8, mod_depth = 0.5, mod_fb = 0, swap = false)
    TrackParams(vol, pan, pitch, mute, solo, eq_low, eq_mid, eq_midf, eq_high,
                mod, mod_mix, mod_rate, mod_depth, mod_fb, swap)
end
Base.copy(t::TrackParams) = TrackParams((getfield(t, f) for f in fieldnames(TrackParams))...)

has_eq(t::TrackParams) = t.eq_low != 0 || t.eq_mid != 0 || t.eq_high != 0
"Track needs its own effect bus (EQ or modulation active)."
has_trackfx(t::TrackParams) = has_eq(t) || t.mod > 1

"Select effect `name` and set its default rate, depth and feedback."
function set_mod!(t::TrackParams, name::AbstractString)
    k = findfirst(==(name), MOD_NAMES)
    k === nothing && error(L("Unbekannter Effekt {1} (erlaubt: {2})", name, join(MOD_NAMES, ", ")))
    t.mod = k
    if haskey(MOD_DEFAULTS, name)
        d = MOD_DEFAULTS[name]
        t.mod_mix = d.mix; t.mod_rate = d.rate; t.mod_depth = d.depth; t.mod_fb = d.fb
    end
    return t
end

"""
Timing of the ornaments, per song: distances in ms (flam: grace note before the stroke; drag:
distance between its strokes, the grace notes come 2× and 1× before the stroke; buzz: distance of
the bounces) and the volume of the grace notes as a factor.
"""
mutable struct OrnTuning
    flam_ms::Float64
    drag_ms::Float64
    buzz_ms::Float64
    grace::Float64
end
OrnTuning(; flam_ms = 30.0, drag_ms = 45.0, buzz_ms = 16.0, grace = 1.0) = OrnTuning(flam_ms, drag_ms, buzz_ms, grace)
Base.copy(o::OrnTuning) = OrnTuning(o.flam_ms, o.drag_ms, o.buzz_ms, o.grace)
const ORN_TUNING_RANGES = (flam_ms = 10:1:80, drag_ms = 15:1:80, buzz_ms = 8:1:40, grace = 0.2:0.05:1.5)

mutable struct Song
    name::String
    bpm::Float64
    swing::Float64               # position of the off-beat note: 0.5 = straight, 2/3 = triplet, 0.75 = dotted
    swing_on::Int                # swing base: 0 = auto, 8 = on 8ths, 16 = on 16ths
    steps_per_beat::Int          # 4 = 16ths, 3 = 8th triplets (shuffle/jazz), 6 = 16th triplets, 2 = 8ths, 8 = 32nds
    patterns::Vector{Pattern}
    chain::Vector{Int}           # order of the patterns in song mode/export
    tracks::Vector{TrackParams}
    kit::String
    fx::String
    fxmix::Float64
    master::Float64
    # Export / practice
    repeats::Int                 # how often the chain repeats in the export
    countin::Int                 # count-in bars
    click::Bool                  # mix the metronome click into the export
    mono::Bool                   # mono output (playback and export)
    swap_lr::Bool                # swap left and right channel (playback and export)
    loop::Bool                   # export as seamless loop (no count-in, tail folded onto the start)
    orn::OrnTuning               # timing of flam, drag and buzz roll
end

"Neutral swing value per grid: straight for 8ths/16ths, exact triplet for triplet grids."
default_swing(steps_per_beat) = steps_per_beat in (3, 6) ? 2 / 3 : 0.5

function Song(; name = "Neu", bpm = 100.0, swing = nothing, swing_on = 0, steps_per_beat = 4,   # i18n-ok: default song name
              patterns = [Pattern(16)], chain = [1], kit = "CrocellKit", fx = "Clean",
              fxmix = 0.25, master = 0.8, repeats = 8, countin = 1, click = false, mono = false,
              swap_lr = false, loop = false, orn = OrnTuning())
    swing_on in (0, 8, 16) || error(L("swing_on muss 0 (Auto), 8 oder 16 sein"))
    swing = something(swing, default_swing(steps_per_beat))
    Song(name, bpm, swing, swing_on, steps_per_beat, patterns, chain,
         [TrackParams() for _ in 1:NTRACKS], kit, fx, fxmix, master, repeats, countin, click, mono, swap_lr, loop, orn)
end

function Base.copy(s::Song)
    Song(s.name, s.bpm, s.swing, s.swing_on, s.steps_per_beat, copy.(s.patterns), copy(s.chain),
         copy.(s.tracks), s.kit, s.fx, s.fxmix, s.master, s.repeats, s.countin, s.click, s.mono, s.swap_lr, s.loop,
         copy(s.orn))
end

beats_per_bar(s::Song, p::Pattern) = max(1, cld(p.steps, s.steps_per_beat))

"Tempo of pattern `p` in song `s`: its own tempo if set, else the song tempo."
pattern_bpm(s::Song, p::Union{Pattern,Nothing}) = p !== nothing && p.bpm > 0 ? p.bpm : s.bpm
has_pattern_tempo(s::Song) = any(p -> p.bpm > 0, s.patterns)

# ---------------------------------------------------------------------------
# Text representation:  "X...x...X.x.x..."
# ---------------------------------------------------------------------------

function level_from_char(c::Char)
    c in ('.', '-', ' ', '_') && return UInt8(0)
    c == 'o' && return UInt8(1)
    c in ('x', '*') && return UInt8(2)
    c in ('X', '#') && return UInt8(3)
    error(L("Unbekanntes Rasterzeichen '{1}' (erlaubt: . o x X)", c))
end

row_string(p::Pattern, t::Int) = String([LEVEL_CHARS[p.grid[t, s]+1] for s in 1:p.steps])

"Ornament of the hit at track `t`, step `s` (0 if there is no hit)."
ornament(p::Pattern, t::Int, s::Int) = p.grid[t, s] > 0 ? p.orn[t, s] : 0x00

orn_string(p::Pattern, t::Int) = String([ORN_CHARS[ornament(p, t, s)+1] for s in 1:p.steps])
has_orn(p::Pattern, t::Int) = any(s -> ornament(p, t, s) > 0, 1:p.steps)

function orn_from_char(c::Char)
    c in ('.', '-', ' ', '_') && return UInt8(0)
    k = findfirst(==(c), ORN_CHARS)
    k === nothing && error(L("Unbekanntes Verzierungszeichen '{1}' (erlaubt: . 2 z f r)", c))
    return UInt8(k - 1)
end

"Sets the ornaments from `Dict(track_id => \"..f...2.\")` (TOML key `orn` of a pattern)."
function set_orns!(p::Pattern, orns::AbstractDict)
    for (id, str) in orns
        t = track_index(String(id))
        t === nothing && continue
        for (s, c) in enumerate(collect(str))
            s > MAXSTEPS && break
            p.orn[t, s] = orn_from_char(c)
        end
    end
    return p
end

"Pattern from `Dict(track_id => \"x.x.\")`. Length = longest row (or `steps`)."
function pattern_from_rows(rows::AbstractDict; steps::Union{Nothing,Int} = nothing)
    n = something(steps, maximum(length, values(rows); init = 0))
    n == 0 && (n = 16)
    n = clamp(n, 1, MAXSTEPS)
    p = Pattern(n)
    for (id, str) in rows
        t = track_index(String(id))
        t === nothing && (@warn L("Unbekannte Spur {1} ignoriert", id); continue)
        for (s, c) in enumerate(collect(str))
            s > MAXSTEPS && break
            p.grid[t, s] = level_from_char(c)
        end
    end
    return p
end

"Readable representation of a pattern (e.g. for the REPL)."
function Base.show(io::IO, ::MIME"text/plain", p::Pattern)
    println(io, "Pattern ($(p.steps) Steps)")
    w = maximum(length ∘ last, TRACKS)
    for t in 1:NTRACKS
        any(!iszero, @view p.grid[t, 1:p.steps]) || continue
        println(io, "  ", rpad(TRACKS[t][2], w), "  ", row_string(p, t))
        has_orn(p, t) && println(io, "  ", rpad("", w), "  ", orn_string(p, t))
    end
end

# ---------------------------------------------------------------------------
# Save / load (TOML, hand-editable)
# ---------------------------------------------------------------------------

function song_to_dict(s::Song)
    d = Dict{String,Any}(
        "name" => s.name, "bpm" => s.bpm, "swing" => s.swing, "swing_on" => s.swing_on, "swing_version" => 2, "steps_per_beat" => s.steps_per_beat,
        "chain" => s.chain, "kit" => s.kit, "fx" => s.fx, "fxmix" => s.fxmix, "master" => s.master,
        "repeats" => s.repeats, "countin" => s.countin, "click" => s.click, "mono" => s.mono, "swap_lr" => s.swap_lr, "loop" => s.loop,
        "pattern" => [pattern_to_dict(p) for p in s.patterns],
        "track" => Dict(TRACK_IDS[t] => track_to_dict(tp) for (t, tp) in enumerate(s.tracks)),
    )
    o = orn_tuning_dict(s.orn)
    isempty(o) || (d["ornaments"] = o)
    return d
end

"Ornament timing as TOML table; only the values that differ from the defaults."
function orn_tuning_dict(o::OrnTuning)
    def = OrnTuning()
    Dict{String,Any}(String(f) => getfield(o, f) for f in fieldnames(OrnTuning) if getfield(o, f) != getfield(def, f))
end

function orn_tuning_from_dict(d::AbstractDict)
    o = OrnTuning()
    for f in fieldnames(OrnTuning)
        v = get(d, String(f), nothing)
        v isa Real && setfield!(o, f, clamp(Float64(v), extrema(getfield(ORN_TUNING_RANGES, f))...))
    end
    return o
end

"Pattern as TOML table; ornaments (`orn`) only if there are any."
function pattern_to_dict(p::Pattern)
    d = Dict{String,Any}("steps" => p.steps,
                         "rows" => Dict(TRACK_IDS[t] => row_string(p, t)
                                        for t in 1:NTRACKS if any(!iszero, @view p.grid[t, 1:p.steps])))
    orns = Dict(TRACK_IDS[t] => orn_string(p, t) for t in 1:NTRACKS if has_orn(p, t))
    isempty(orns) || (d["orn"] = orns)
    p.bpm > 0 && (d["bpm"] = p.bpm)
    return d
end

"Track settings; effect parameters only if they differ from the defaults (keeps the file readable)."
function track_to_dict(tp::TrackParams)
    d = Dict{String,Any}("vol" => tp.vol, "pan" => tp.pan, "pitch" => tp.pitch, "mute" => tp.mute, "solo" => tp.solo)
    tp.swap && (d["swap_lr"] = true)
    r(x) = round(Float64(x); digits = 3)
    if has_eq(tp)
        d["eq_low"] = r(tp.eq_low); d["eq_mid"] = r(tp.eq_mid); d["eq_high"] = r(tp.eq_high)
        d["eq_mid_freq"] = r(tp.eq_midf)
    end
    if tp.mod > 1
        d["mod"] = MOD_NAMES[tp.mod]
        d["mod_mix"] = r(tp.mod_mix); d["mod_rate"] = r(tp.mod_rate)
        d["mod_depth"] = r(tp.mod_depth); d["mod_feedback"] = r(tp.mod_fb)
    end
    return d
end

function track_from_dict(tp::AbstractDict)
    t = TrackParams(vol = get(tp, "vol", 1.0), pan = get(tp, "pan", 0.0), pitch = get(tp, "pitch", 0.0),
                    mute = get(tp, "mute", false), solo = get(tp, "solo", false), swap = get(tp, "swap_lr", false),
                    eq_low = get(tp, "eq_low", 0.0), eq_mid = get(tp, "eq_mid", 0.0),
                    eq_midf = get(tp, "eq_mid_freq", EQ_MIDF_DEFAULT), eq_high = get(tp, "eq_high", 0.0))
    if haskey(tp, "mod")
        name = String(tp["mod"])
        if name in MOD_NAMES
            set_mod!(t, name)
        else
            @warn L("Unbekannter Effekt {1} ignoriert", name)
        end
    end
    t.mod_mix = get(tp, "mod_mix", t.mod_mix)
    t.mod_rate = get(tp, "mod_rate", t.mod_rate)
    t.mod_depth = get(tp, "mod_depth", t.mod_depth)
    t.mod_fb = clamp(get(tp, "mod_feedback", t.mod_fb), 0, 0.9)
    t.eq_midf = clamp(t.eq_midf, 200, 6000)
    return t
end

function song_from_dict(d::AbstractDict)
    function pat(p)
        q = set_orns!(pattern_from_rows(get(p, "rows", Dict()); steps = get(p, "steps", 16)), get(p, "orn", Dict()))
        b = get(p, "bpm", 0)
        b isa Real && b > 0 && (q.bpm = clamp(Float64(b), BPM_RANGE...))
        return q
    end
    pats = [pat(p) for p in get(d, "pattern", [])]
    isempty(pats) && push!(pats, Pattern(16))
    s = Song(name = get(d, "name", "Neu"), bpm = get(d, "bpm", 100.0), swing = get(d, "swing", 0.5),   # i18n-ok: default song name
             swing_on = get(d, "swing_on", 0),
             steps_per_beat = get(d, "steps_per_beat", 4), patterns = pats,
             chain = Int.(get(d, "chain", [1])), kit = get(d, "kit", "CrocellKit"), fx = get(d, "fx", "Clean"),
             fxmix = get(d, "fxmix", 0.25), master = get(d, "master", 0.8), repeats = get(d, "repeats", 8),
             countin = get(d, "countin", 1), click = get(d, "click", false),
             mono = get(d, "mono", false), swap_lr = get(d, "swap_lr", false),
             loop = get(d, "loop", false), orn = orn_tuning_from_dict(get(d, "ornaments", Dict())))
    # Up to v0.1: swing had no effect on triplet grids, so 0.5 (= exact triplets) was saved
    if s.steps_per_beat in (3, 6) && s.swing == 0.5 && get(d, "swing_version", 1) < 2
        s.swing = 2 / 3
    end
    filter!(i -> 1 <= i <= length(pats), s.chain)
    isempty(s.chain) && push!(s.chain, 1)
    for (id, tp) in get(d, "track", Dict())
        t = track_index(id)
        t === nothing && continue
        s.tracks[t] = track_from_dict(tp)
    end
    return s
end

function save_song(path::AbstractString, s::Song)
    mkpath(dirname(abspath(path)))
    open(io -> TOML.print(io, song_to_dict(s); sorted = true), path, "w")
    return path
end

"File name (without .toml) for a song name: letters, digits, - and spaces, the rest becomes _."
safe_song_name(name::AbstractString) = replace(strip(name), r"[^\w\-äöüÄÖÜß ]" => "_")   # i18n-ok: regex

load_song(path::AbstractString) = song_from_dict(TOML.parsefile(path))

"Chain from text like \"1 1 1 2\" or \"1x3 2\" (= 1 1 1 2)."
function parse_chain(str::AbstractString, npat::Int)
    out = Int[]
    for tok in split(replace(str, ',' => ' '))
        m = match(r"^(\d+)(?:[x\*](\d+))?$", tok)
        m === nothing && continue
        i = parse(Int, m[1]); n = m[2] === nothing ? 1 : parse(Int, m[2])
        1 <= i <= npat && append!(out, fill(i, n))
    end
    return out
end

chain_string(c::Vector{Int}) = join(c, " ")
