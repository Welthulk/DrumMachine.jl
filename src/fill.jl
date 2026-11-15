# Fill-Generator: ersetzt die letzten Schläge eines Patterns durch einen Fill.
#
# Jeder Stil liefert für die Fill-Strecke (n Steps, spb Steps pro Schlag) eine Liste
# (Step in der Strecke, Spur-ID, Stufe). Alles andere in der Strecke wird gelöscht,
# der Groove davor bleibt erhalten. Passt in jedes Raster (16tel, Triolen, 8tel).

const _O, _N, _A = 0x01, 0x02, 0x03      # Ghost, normal, Akzent

beatstart(i, spb) = (i - 1) % spb == 0

"Snare auf jedem Step, Akzent am Ende."
function fill_wirbel(n, spb)
    hits = [(i, "Snare", i == n ? _A : beatstart(i, spb) ? _A : _N) for i in 1:n]
    push!(hits, (1, "Kick", _N))
    hits
end

"Snare → Tom → Floor Tom, gleichmäßig über die Strecke verteilt."
function fill_abgang(n, spb)
    drums = ("Snare", "Tom", "FloorTom")
    hits = [(i, drums[cld(3i, n)], beatstart(i, spb) ? _A : _N) for i in 1:n]
    push!(hits, (n, "Kick", _N))
    hits
end

"Erster Schlag Snare, danach Tom und Floor Tom im Wechsel, Bassdrum auf den Schlägen."
function fill_wechsel(n, spb)
    hits = Tuple{Int,String,UInt8}[]
    for i in 1:n
        d = i <= spb ? "Snare" : isodd(i) ? "Tom" : "FloorTom"
        push!(hits, (i, d, beatstart(i, spb) ? _A : _N))
        beatstart(i, spb) && push!(hits, (i, "Kick", _N))
    end
    hits
end

"Snare und Floor Tom unisono im 3er-Abstand (3-3-2-Gefühl), dazu Bassdrum."
function fill_akzente(n, _)
    hits = Tuple{Int,String,UInt8}[]
    for i in 1:3:n
        append!(hits, [(i, "Snare", _A), (i, "FloorTom", _A), (i, "Kick", _N)])
    end
    hits
end

"Snare-Crescendo: Ghost Notes, dann normal, Akzente zum Schluss; Floor Tom auf dem letzten Step."
function fill_crescendo(n, _)
    lv(i) = i <= n ÷ 3 ? _O : i <= 2n ÷ 3 ? _N : _A
    hits = [(i, "Snare", lv(i)) for i in 1:n]
    append!(hits, [(n, "FloorTom", _A), (n, "Kick", _N)])
    hits
end

"Ganzer Takt rund ums Set: Snare, Snare, Tom, Floor Tom (je Schlag), Bassdrum auf den Schlägen."
function fill_rundlauf(n, spb)
    nb = cld(n, spb)
    hits = Tuple{Int,String,UInt8}[]
    for i in 1:n
        b = cld(i, spb)                         # Schlag in der Strecke
        d = b <= nb ÷ 2 ? "Snare" : b < nb ? "Tom" : "FloorTom"
        push!(hits, (i, d, beatstart(i, spb) ? _A : _N))
        beatstart(i, spb) && push!(hits, (i, "Kick", _N))
    end
    hits
end

"Fill-Stile: (Name, Länge in Schlägen, Generator)."
const FILL_STYLES = [
    ("Snare-Wirbel",          1, fill_wirbel),
    ("Tom-Abgang",            1, fill_abgang),
    ("Snare/Tom-Wechsel",     2, fill_wechsel),
    ("Akzente 3-3-2",         2, fill_akzente),
    ("Snare-Crescendo",       2, fill_crescendo),
    ("Tom-Abgang (2 Schläge)", 2, fill_abgang),
    ("Ganzer Takt",           4, fill_rundlauf),
]

"""
    make_fill(p, steps_per_beat, style = 1) -> Pattern

Kopie von `p`, deren letzte Schläge durch den Fill `FILL_STYLES[style]` ersetzt sind
(Stil wird zyklisch gewählt, also ist jede ganze Zahl erlaubt).
"""
function make_fill(p::Pattern, spb::Int, style::Integer = 1)
    _, beats, gen = FILL_STYLES[mod1(style, length(FILL_STYLES))]
    n = min(beats * spb, p.steps)
    off = p.steps - n
    q = copy(p)
    q.grid[:, off+1:p.steps] .= 0x00
    for (i, id, lv) in gen(n, spb)
        q.grid[track_index(id), off+i] = lv
    end
    return q
end

fill_name(style::Integer) = FILL_STYLES[mod1(style, length(FILL_STYLES))][1]
