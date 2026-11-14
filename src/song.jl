# Song-Modell: Patterns (Raster Spuren × Steps), Kette, Spur-Einstellungen, Presets, TOML-I/O.

const MAXSTEPS = 32

# Rasterwerte: 0 = aus, 1 = Ghost (leise), 2 = normal, 3 = Akzent
const LEVEL_CHARS = ('.', 'o', 'x', 'X')
const LEVEL_NAMES = ("aus", "Ghost", "normal", "Akzent")

mutable struct Pattern
    steps::Int
    grid::Matrix{UInt8}          # NTRACKS × MAXSTEPS
end
Pattern(steps::Int = 16) = Pattern(steps, zeros(UInt8, NTRACKS, MAXSTEPS))
Base.copy(p::Pattern) = Pattern(p.steps, copy(p.grid))

mutable struct TrackParams
    vol::Float32                 # 0 … 1.5
    pan::Float32                 # Versatz zum Kit-Panorama, -1 … 1
    pitch::Float32               # Halbtöne
    mute::Bool
    solo::Bool
end
TrackParams() = TrackParams(1f0, 0f0, 0f0, false, false)
Base.copy(t::TrackParams) = TrackParams(t.vol, t.pan, t.pitch, t.mute, t.solo)

mutable struct Song
    name::String
    bpm::Float64
    swing::Float64               # 0.5 = gerade … 0.75 = stark geswingt (nur bei 2/4 Steps pro Schlag)
    steps_per_beat::Int          # 4 = Sechzehntel, 3 = Triolen (Shuffle/Jazz), 2 = Achtel
    patterns::Vector{Pattern}
    chain::Vector{Int}           # Reihenfolge der Patterns im Song-Modus/Export
    tracks::Vector{TrackParams}
    kit::String
    fx::String
    fxmix::Float64
    master::Float64
    # Export / Üben
    repeats::Int                 # Wie oft die Kette im Export wiederholt wird
    countin::Int                 # Einzähler-Takte
    click::Bool                  # Metronom-Klick in den Export mischen
end

function Song(; name = "Neu", bpm = 100.0, swing = 0.5, steps_per_beat = 4,
              patterns = [Pattern(16)], chain = [1], kit = "BlackPearl", fx = "Clean",
              fxmix = 0.25, master = 0.8, repeats = 8, countin = 1, click = false)
    Song(name, bpm, swing, steps_per_beat, patterns, chain,
         [TrackParams() for _ in 1:NTRACKS], kit, fx, fxmix, master, repeats, countin, click)
end

function Base.copy(s::Song)
    Song(s.name, s.bpm, s.swing, s.steps_per_beat, copy.(s.patterns), copy(s.chain),
         copy.(s.tracks), s.kit, s.fx, s.fxmix, s.master, s.repeats, s.countin, s.click)
end

beats_per_bar(s::Song, p::Pattern) = max(1, cld(p.steps, s.steps_per_beat))

# ---------------------------------------------------------------------------
# Textdarstellung:  "X...x...X.x.x..."
# ---------------------------------------------------------------------------

function level_from_char(c::Char)
    c in ('.', '-', ' ', '_') && return UInt8(0)
    c == 'o' && return UInt8(1)
    c in ('x', '*') && return UInt8(2)
    c in ('X', '#') && return UInt8(3)
    error("Unbekanntes Rasterzeichen '$c' (erlaubt: . o x X)")
end

row_string(p::Pattern, t::Int) = String([LEVEL_CHARS[p.grid[t, s]+1] for s in 1:p.steps])

"Pattern aus `Dict(spur_id => \"x.x.\")`. Länge = längste Zeile (oder `steps`)."
function pattern_from_rows(rows::AbstractDict; steps::Union{Nothing,Int} = nothing)
    n = something(steps, maximum(length, values(rows); init = 0))
    n == 0 && (n = 16)
    n = clamp(n, 1, MAXSTEPS)
    p = Pattern(n)
    for (id, str) in rows
        t = track_index(String(id))
        t === nothing && (@warn "Unbekannte Spur $id ignoriert"; continue)
        for (s, c) in enumerate(collect(str))
            s > MAXSTEPS && break
            p.grid[t, s] = level_from_char(c)
        end
    end
    return p
end

"Lesbare Darstellung eines Patterns (z. B. für die REPL)."
function Base.show(io::IO, ::MIME"text/plain", p::Pattern)
    println(io, "Pattern ($(p.steps) Steps)")
    w = maximum(length ∘ last, TRACKS)
    for t in 1:NTRACKS
        any(!iszero, @view p.grid[t, 1:p.steps]) || continue
        println(io, "  ", rpad(TRACKS[t][2], w), "  ", row_string(p, t))
    end
end

# ---------------------------------------------------------------------------
# Presets – Standard-Grooves zum Üben
# ---------------------------------------------------------------------------

P(; steps = nothing, kw...) = pattern_from_rows(Dict(String(k) => v for (k, v) in kw); steps)

const PRESET_NAMES = ["Leer", "Rock 8tel", "Rock 16tel", "Shuffle", "Disco",
                      "Funk Ghost Notes", "Jazz Ride", "Walzer 3/4", "Reggae One Drop", "Bossa Nova"]

function preset(name::AbstractString)
    if name == "Leer"
        return Song(name = "Leer")
    elseif name == "Rock 8tel"
        groove = P(HiHat = "x.x.x.x.x.x.x.x.", Snare = "....X.......X...", Kick = "X.......X.X.....")
        crash  = P(Crash = "X...............", HiHat = "..x.x.x.x.x.x.x.", Snare = "....X.......X...",
                   Kick = "X.......X.X.....")
        fill   = P(HiHat = "x.x.x.x.x.x.....", Snare = "....X.......Xx..", Tom = "..............x.",
                   FloorTom = "...............x", Kick = "X.......X.X.....")
        return Song(name = name, bpm = 100, patterns = [crash, groove, fill], chain = [1, 2, 2, 3])
    elseif name == "Rock 16tel"
        g = P(HiHat = "xoxoxoxoxoxoxoxo", Snare = "....X.......X...", Kick = "X.....X.X.X.....")
        return Song(name = name, bpm = 85, patterns = [g])
    elseif name == "Shuffle"
        g = P(HiHat = "x.xx.xx.xx.x", Snare = "...X.....X..", Kick = "X.....X.....")
        f = P(HiHat = "x.xx.xx.....", Snare = "...X.....XoX", Tom = "......xx....", FloorTom = "...........X",
              Kick = "X.....X.....")
        return Song(name = name, bpm = 90, steps_per_beat = 3, patterns = [g, f], chain = [1, 1, 1, 2])
    elseif name == "Disco"
        g = P(Kick = "X...X...X...X...", Snare = "....X.......X...", HiHat = "x...x...x...x...",
              HHOpen = "..x...x...x...x.")
        return Song(name = name, bpm = 118, patterns = [g])
    elseif name == "Funk Ghost Notes"
        g = P(HiHat = "x.x.x.x.x.x.x.x.", Snare = "....X..o.o..X..o", Kick = "X.x.......X..x..")
        return Song(name = name, bpm = 92, patterns = [g])
    elseif name == "Jazz Ride"
        g = P(Ride = "x..x.xx..x.x", HHPedal = "...x.....x..", Kick = "o..o..o..o..", Snare = "........o...")
        return Song(name = name, bpm = 130, steps_per_beat = 3, patterns = [g])
    elseif name == "Walzer 3/4"
        g = P(Kick = "X...........", Snare = "....x...x...", HiHat = "x.x.x.x.x.x.")
        return Song(name = name, bpm = 120, patterns = [g])
    elseif name == "Reggae One Drop"
        g = P(Kick = "........X.......", Rim = "........X.......", HiHat = "x.o.x.o.x.o.x.o.")
        return Song(name = name, bpm = 75, swing = 0.6, patterns = [g])
    elseif name == "Bossa Nova"
        g = P(Rim = "X..X..X...X..X..", Kick = "X..xX..xX..xX..x", HiHat = "x.x.x.x.x.x.x.x.")
        return Song(name = name, bpm = 130, patterns = [g])
    end
    error("Unbekanntes Preset $name")
end

# ---------------------------------------------------------------------------
# Speichern / Laden (TOML, von Hand editierbar)
# ---------------------------------------------------------------------------

function song_to_dict(s::Song)
    Dict{String,Any}(
        "name" => s.name, "bpm" => s.bpm, "swing" => s.swing, "steps_per_beat" => s.steps_per_beat,
        "chain" => s.chain, "kit" => s.kit, "fx" => s.fx, "fxmix" => s.fxmix, "master" => s.master,
        "repeats" => s.repeats, "countin" => s.countin, "click" => s.click,
        "pattern" => [Dict{String,Any}("steps" => p.steps,
                                       "rows" => Dict(TRACK_IDS[t] => row_string(p, t)
                                                      for t in 1:NTRACKS if any(!iszero, @view p.grid[t, 1:p.steps])))
                      for p in s.patterns],
        "track" => Dict(TRACK_IDS[t] => Dict{String,Any}("vol" => tp.vol, "pan" => tp.pan, "pitch" => tp.pitch,
                                                          "mute" => tp.mute, "solo" => tp.solo)
                        for (t, tp) in enumerate(s.tracks)),
    )
end

function song_from_dict(d::AbstractDict)
    pats = [pattern_from_rows(get(p, "rows", Dict()); steps = get(p, "steps", 16)) for p in get(d, "pattern", [])]
    isempty(pats) && push!(pats, Pattern(16))
    s = Song(name = get(d, "name", "Neu"), bpm = get(d, "bpm", 100.0), swing = get(d, "swing", 0.5),
             steps_per_beat = get(d, "steps_per_beat", 4), patterns = pats,
             chain = Int.(get(d, "chain", [1])), kit = get(d, "kit", "BlackPearl"), fx = get(d, "fx", "Clean"),
             fxmix = get(d, "fxmix", 0.25), master = get(d, "master", 0.8), repeats = get(d, "repeats", 8),
             countin = get(d, "countin", 1), click = get(d, "click", false))
    filter!(i -> 1 <= i <= length(pats), s.chain)
    isempty(s.chain) && push!(s.chain, 1)
    for (id, tp) in get(d, "track", Dict())
        t = track_index(id)
        t === nothing && continue
        s.tracks[t] = TrackParams(get(tp, "vol", 1.0), get(tp, "pan", 0.0), get(tp, "pitch", 0.0),
                                  get(tp, "mute", false), get(tp, "solo", false))
    end
    return s
end

function save_song(path::AbstractString, s::Song)
    mkpath(dirname(abspath(path)))
    open(io -> TOML.print(io, song_to_dict(s); sorted = true), path, "w")
    return path
end

load_song(path::AbstractString) = song_from_dict(TOML.parsefile(path))

"Kette aus Text wie \"1 1 1 2\" oder \"1x3 2\" (= 1 1 1 2)."
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
