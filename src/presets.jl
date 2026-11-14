# Groove-Bibliothek zum Üben. Jedes Preset ist eine Funktion, die einen frischen `Song` liefert.
#
# Rasterzeichen:  . = aus   o = Ghost   x = normal   X = Akzent
# Spuren:         Kick Snare Rim HiHat HHOpen HHPedal Tom FloorTom Ride RideBell Crash
#
# 16tel-Raster (steps_per_beat = 4), Position im Takt:
#   1 e + a 2 e + a 3 e + a 4 e + a
#   1 2 3 4 5 6 7 8 9 ...          (Step-Nummer)

function P(; steps = nothing, kw...)
    rows = Dict(String(k) => v for (k, v) in kw)
    lens = unique(length.(values(rows)))
    length(lens) == 1 || error("Preset-Zeilen unterschiedlich lang: $(Dict(k => length(v) for (k, v) in rows))")
    return pattern_from_rows(rows; steps)
end

"Kopie von `p` mit Crash auf der Eins (HiHat/Ride auf der Eins entfällt)."
function with_crash(p::Pattern)
    q = copy(p)
    for id in ("HiHat", "HHOpen", "Ride", "RideBell")
        q.grid[track_index(id), 1] = 0x00
    end
    q.grid[track_index("Crash"), 1] = 0x03
    return q
end

"Kette: Crash-Takt, (n-2)× Groove, Fill  →  Patterns [crash, groove, fill]."
form(n) = vcat(1, fill(2, n - 2), 3)

const PRESETS = Pair{String,Function}[

    "Leer" => () -> Song(name = "Leer"),

    # ------------------------------------------------------------------ Rock / Pop
    "Rock: 8tel" => function ()
        g = P(HiHat = "x.x.x.x.x.x.x.x.",
              Snare = "....X.......X...",
              Kick  = "X.......X.X.....")
        f = P(HiHat = "x.x.x.x.x.x.....",
              Snare = "....X.......Xx..",
              Tom   = "..............x.",
              FloorTom = "...............x",
              Kick  = "X.......X.X.....")
        Song(name = "Rock: 8tel", bpm = 100, patterns = [with_crash(g), g, f], chain = form(4))
    end,

    "Rock: 16tel" => function ()
        g = P(HiHat = "xoxoxoxoxoxoxoxo",
              Snare = "....X.......X...",
              Kick  = "X.....X.X.X.....")
        Song(name = "Rock: 16tel", bpm = 85, patterns = [g])
    end,

    "Rock: Half-Time" => function ()
        g = P(HiHat = "x.x.x.x.x.x.x.x.",
              Snare = "........X.......",
              Kick  = "X.....X...X.....")
        Song(name = "Rock: Half-Time", bpm = 140, patterns = [g])
    end,

    "Rock: Punk" => function ()
        g = P(HiHat = "x.x.x.x.x.x.x.x.",
              Snare = "....X.......X...",
              Kick  = "X.X.....X.X.....")
        Song(name = "Rock: Punk", bpm = 175, patterns = [g])
    end,

    "Rock'n'Roll" => function ()
        g = P(Ride  = "x.x.x.x.x.x.x.x.",
              Snare = "....X.......X...",
              Kick  = "X.......X.......")
        Song(name = "Rock'n'Roll", bpm = 160, swing = 0.64, patterns = [g])
    end,

    "Pop: Ballade" => function ()
        g = P(HiHat = "x.x.x.x.x.x.x.x.",
              Rim   = "....X.......X...",
              Kick  = "X......xX.......")
        f = P(HiHat = "x.x.x.x.x.x.....",
              Rim   = "....X...........",
              Snare = "............xx..",
              Tom   = "..............x.",
              FloorTom = "...............x",
              Kick  = "X......xX.......")
        Song(name = "Pop: Ballade", bpm = 72, patterns = [with_crash(g), g, f], chain = form(4))
    end,

    "Pop: Motown" => function ()
        g = P(HiHat = "x.x.x.x.x.x.x.x.",
              Snare = "x...X...x...X...",
              Kick  = "X.x...x.X.x...x.")
        Song(name = "Pop: Motown", bpm = 120, patterns = [g])
    end,

    "Pop: Disco" => function ()
        g = P(Kick   = "X...X...X...X...",
              Snare  = "....X.......X...",
              HiHat  = "x...x...x...x...",
              HHOpen = "..x...x...x...x.")
        Song(name = "Pop: Disco", bpm = 118, patterns = [g])
    end,

    "Country: Train Beat" => function ()
        g = P(Snare   = "ooooXoooooooXooo",
              Kick    = "X.......X.......",
              HHPedal = "..x...x...x...x.")
        Song(name = "Country: Train Beat", bpm = 120, patterns = [g])
    end,

    # ------------------------------------------------------------------ Funk
    "Funk: Ghost Notes" => function ()
        g = P(HiHat = "x.x.x.x.x.x.x.x.",
              Snare = "....X..o.o..X..o",
              Kick  = "X.x.......X..x..")
        Song(name = "Funk: Ghost Notes", bpm = 92, patterns = [g])
    end,

    "Funk: Oakland (Tower-of-Power-Stil)" => function ()
        # Garibaldi-artig: 16tel-Hihat mit Akzenten auf den Vierteln, offene Hihat auf der 4+,
        # Ghost Notes zwischen Bassdrum und Backbeat.
        g = P(HiHat  = "XoxoXoxoXoxoXo.o",
              HHOpen = "..............X.",
              Snare  = ".o..X.o..o..X.o.",
              Kick   = "X.x....x..x..x..")
        v = P(HiHat  = "XoxoXo.oXoxoXo.o",
              HHOpen = "......X.......X.",
              Snare  = ".o..X..o.oo.X.o.",
              Kick   = "X.x....x.x...x.x")
        Song(name = "Funk: Oakland (Tower-of-Power-Stil)", bpm = 104, patterns = [g, v], chain = [1, 1, 1, 2])
    end,

    "Funk: What-Is-Hip-Stil (Tower of Power)" => function ()
        # Annäherung an den Garibaldi-Groove: schnelles 16tel-Funk-Tempo, synkopierte Bassdrum,
        # Ghost Notes zwischen den Backbeats, offene Hihat auf der 4+ (Variation zusätzlich auf der 2+).
        #             1 e + a 2 e + a 3 e + a 4 e + a
        a = P(HiHat  = "x.x.x.x.x.x.x...",
              HHOpen = "..............X.",
              Snare  = ".o..X..o.o..X..o",
              Kick   = "X..x..x..x....x.")
        b = P(HiHat  = "x.x.x...x.x.x...",
              HHOpen = "......X.......X.",
              Snare  = ".o..X..o.o.oX.o.",
              Kick   = "X..x..x...X..x..")
        Song(name = "Funk: What-Is-Hip-Stil (Tower of Power)", bpm = 124, patterns = [a, b], chain = [1, 1, 1, 2])
    end,

    "Funk: Garibaldi Linear (Oakland)" => function ()
        # Linear im Tower-of-Power-Stil: auf jedem 16tel genau ein Instrument,
        # offene Hihat auf der 4+ als Höhepunkt vor der Eins.
        #             1 e + a 2 e + a 3 e + a 4 e + a
        g = P(Kick   = "X.....X.X..X...x",
              Snare  = "..o.X....o..X...",
              HiHat  = ".x.x.x.x..x..x..",
              HHOpen = "..............X.")
        Song(name = "Funk: Garibaldi Linear (Oakland)", bpm = 100, patterns = [g])
    end,

    "Funk: Oakland Half-Time" => function ()
        # Half-Time-Funk: Backbeat nur auf der 3, durchlaufende 16tel-Hihat mit Viertel-Akzenten,
        # Ghost Notes und synkopierte Bassdrum.
        g = P(HiHat = "XxxxXxxxXxxxXxx.",
              HHOpen = "...............X",
              Snare = ".o..o...X.o..o..",
              Kick  = "X.x.....x..x.x..")
        Song(name = "Funk: Oakland Half-Time", bpm = 92, patterns = [g])
    end,

    "Funk: Linear" => function ()
        # Linear: nie zwei Instrumente gleichzeitig.
        g = P(Kick  = "X..x...x.x....x.",
              Snare = "....X.o....oX...",
              HiHat = ".xx..x..x.x..x.x")
        Song(name = "Funk: Linear", bpm = 96, patterns = [g])
    end,

    "Funk: 16tel Zwei-Hand-Hihat" => function ()
        # Hihat mit beiden Händen, die Snare ersetzt die Hihat auf dem Backbeat.
        g = P(HiHat = "xoxo.oxoxoxo.oxo",
              Snare = "....X.......X...",
              Kick  = "X..X..X...X..X..")
        Song(name = "Funk: 16tel Zwei-Hand-Hihat", bpm = 100, patterns = [g])
    end,

    # ------------------------------------------------------------------ Blues
    "Blues: Shuffle (12 Takte)" => function ()
        g = P(HiHat = "x.xx.xx.xx.x",
              Snare = "...X.....X..",
              Kick  = "X.....X.....")
        f = P(HiHat = "x.xx.xx.....",
              Snare = "...X.....XoX",
              Tom   = "......xx....",
              FloorTom = "...........X",
              Kick  = "X.....X.....")
        Song(name = "Blues: Shuffle (12 Takte)", bpm = 90, steps_per_beat = 3,
             patterns = [with_crash(g), g, f], chain = form(12), repeats = 3)
    end,

    "Blues: Double Shuffle (Texas)" => function ()
        g = P(HiHat = "x.xx.xx.xx.x",
              Snare = "o.oX.oo.oX.o",
              Kick  = "X.....X.....")
        f = P(HiHat = "x.xx.xx.....",
              Snare = "o.oX.oo.oX..",
              Tom   = "...........x",
              FloorTom = "..........X.",
              Kick  = "X.....X.....")
        Song(name = "Blues: Double Shuffle (Texas)", bpm = 115, steps_per_beat = 3,
             patterns = [with_crash(g), g, f], chain = form(12), repeats = 3)
    end,

    "Blues: Slow Blues 12/8" => function ()
        g = P(HiHat = "XxxXxxXxxXxx",
              Snare = "...X.....X..",
              Kick  = "X.....X..x..")
        f = P(HiHat = "XxxXxxXxx...",
              Snare = "...X.....X..",
              Tom   = "..........x.",
              FloorTom = "...........X",
              Kick  = "X.....X.....")
        Song(name = "Blues: Slow Blues 12/8", bpm = 58, steps_per_beat = 3,
             patterns = [with_crash(g), g, f], chain = form(12), repeats = 2)
    end,

    "Blues: Jump / Swing" => function ()
        g = P(Ride    = "x..x.xx..x.x",
              Snare   = "...X.....X..",
              Kick    = "o..o..o..o..",
              HHPedal = "...x.....x..")
        Song(name = "Blues: Jump / Swing", bpm = 160, steps_per_beat = 3,
             patterns = [with_crash(g), g], chain = vcat(1, fill(2, 11)), repeats = 3)
    end,

    # ------------------------------------------------------------------ Shuffles
    # Triolen-Raster: Swing-Regler verschiebt die dritte Triole (67 % = exakt, 75 % = punktiert).
    # Gerade Raster: Swing-Regler verschiebt das „+“ (auf 8tel) bzw. „e“/„a“ (auf 16tel).

    "Shuffle: Rock-Shuffle" => function ()
        g = P(HiHat = "X.xX.xX.xX.x",
              Snare = "...X.....X..",
              Kick  = "X.x...X.x...")
        f = P(HiHat = "X.xX.x......",
              Snare = "...X..xxx...",
              Tom   = ".........xx.",
              FloorTom = "...........X",
              Kick  = "X.....X.....")
        Song(name = "Shuffle: Rock-Shuffle", bpm = 125, steps_per_beat = 3,
             patterns = [with_crash(g), g, f], chain = form(8), repeats = 2)
    end,

    "Shuffle: Ride-Shuffle" => function ()
        g = P(Ride    = "x.xx.xx.xx.x",
              HHPedal = "...x.....x..",
              Snare   = "...X.....X..",
              Kick    = "X.....X.....")
        Song(name = "Shuffle: Ride-Shuffle", bpm = 140, steps_per_beat = 3, patterns = [g])
    end,

    "Shuffle: Snare-Shuffle (Chicago)" => function ()
        # Die Snare spielt den Shuffle durch (Ghosts + Backbeat), Ride auf den Vierteln.
        g = P(Ride    = "x..x..x..x..",
              Snare   = "o.oX.oo.oX.o",
              HHPedal = "...x.....x..",
              Kick    = "X.....X.....")
        Song(name = "Shuffle: Snare-Shuffle (Chicago)", bpm = 120, steps_per_beat = 3, patterns = [g])
    end,

    "Shuffle: Half-Time (8tel-Triolen)" => function ()
        g = P(HiHat = "x.xx.xx.xx.x",
              Snare = ".o..o.X...o.",
              Kick  = "X.......x...")
        Song(name = "Shuffle: Half-Time (8tel-Triolen)", bpm = 140, steps_per_beat = 3, patterns = [g])
    end,

    "Shuffle: Purdie Half-Time (16tel-Triolen)" => function ()
        # 16tel-Triolen (6 pro Schlag): Hihat-Shuffle, Ghost Notes auf den Mitteltriolen,
        # Backbeat nur auf der 3.
        g = P(HiHat = "x.xx.xx.xx.xx.xx.xx.xx.x",
              Snare = ".o..o..o..o.X...o..o..o.",
              Kick  = "X..........x.........x..")
        Song(name = "Shuffle: Purdie Half-Time (16tel-Triolen)", bpm = 80, steps_per_beat = 6, patterns = [g])
    end,

    "Shuffle: Rosanna-Stil (Porcaro/Purdie)" => function ()
        # Porcaros Variante des Purdie-Shuffles: 16tel-Triolen, Hihat-Shuffle mit Akzent auf der 3,
        # Ghost Notes auf den mittleren Triolen, Backbeat nur auf der 3,
        # Bassdrum-Auftakte vor der 3 und vor der 1.
        #            1 la li + la li 2 . . . . . 3 . . . . . 4 . . . . .
        g = P(HiHat = "x.xx.xx.xx.xX.xx.xx.xx.x",
              Snare = ".o..o..o..o.X...o..o..o.",
              Kick  = "X..........x...x.......x")
        v = P(HiHat  = "x.xx.xx.xx.xX.xx.xx.xx..",
              HHOpen = ".......................X",
              Snare  = ".o..o..o..o.X...o..o.oo.",
              Kick   = "X..........x...x........")
        Song(name = "Shuffle: Rosanna-Stil (Porcaro/Purdie)", bpm = 86, steps_per_beat = 6,
             patterns = [g, v], chain = [1, 1, 1, 2])
    end,

    "Shuffle: Rule-the-World-Stil (Tears for Fears, 12/8)" => function ()
        # Annäherung an den eher untypischen Pop-Shuffle: 12/8 in vier punktierten Schlägen,
        # Snare nur auf der 3 (Half-Time-Gefühl), Hihat-Shuffle, Bassdrum schiebt in die 3.
        #             1 + a 2 + a 3 + a 4 + a
        g = P(HiHat = "x.xx.xx.xx.x",
              Snare = "......X.....",
              Kick  = "X....x...x..")
        Song(name = "Shuffle: Rule-the-World-Stil (Tears for Fears, 12/8)", bpm = 112, steps_per_beat = 3,
             patterns = [g])
    end,

    "Shuffle: Laid-back (58 %)" => function ()
        g = P(HiHat = "x.xx.xx.xx.x",
              Snare = "...X.....X..",
              Kick  = "X.....X.....")
        Song(name = "Shuffle: Laid-back (58 %)", bpm = 100, steps_per_beat = 3, swing = 0.58, patterns = [g])
    end,

    "Shuffle: Hart punktiert (75 %)" => function ()
        g = P(HiHat = "x.xx.xx.xx.x",
              Snare = "...X.....X..",
              Kick  = "X.....X.....")
        Song(name = "Shuffle: Hart punktiert (75 %)", bpm = 100, steps_per_beat = 3, swing = 0.75, patterns = [g])
    end,

    "Shuffle: 8tel-Swing im geraden Raster" => function ()
        # 16tel-Raster, Swing 66 % auf 8tel: das „+“ rutscht auf die dritte Triole.
        g = P(HiHat = "x.x.x.x.x.x.x.x.",
              Snare = "....X.......X...",
              Kick  = "X.....x.X.......")
        Song(name = "Shuffle: 8tel-Swing im geraden Raster", bpm = 110, swing = 0.66, swing_on = 8, patterns = [g])
    end,

    "Shuffle: 16tel-Swing (Funk/Hip-Hop)" => function ()
        g = P(HiHat = "xoxoxoxoxoxoxoxo",
              Snare = "....X..o.o..X...",
              Kick  = "X..x......X..x..")
        Song(name = "Shuffle: 16tel-Swing (Funk/Hip-Hop)", bpm = 90, swing = 0.6, swing_on = 16, patterns = [g])
    end,

    # ------------------------------------------------------------------ Jazz
    "Jazz: Swing Ride" => function ()
        g = P(Ride    = "x..x.xx..x.x",
              HHPedal = "...x.....x..",
              Kick    = "o..o..o..o..",
              Snare   = "........o...")
        Song(name = "Jazz: Swing Ride", bpm = 130, steps_per_beat = 3, patterns = [g])
    end,

    "Jazz: Walzer 3/4" => function ()
        g = P(Ride    = "x..x.xx..",
              HHPedal = "...x..x..",
              Kick    = "o........")
        Song(name = "Jazz: Walzer 3/4", bpm = 140, steps_per_beat = 3, patterns = [g])
    end,

    # ------------------------------------------------------------------ Latin / Reggae
    "Latin: Bossa Nova" => function ()
        g = P(Rim   = "X..X..X...X..X..",
              Kick  = "X..xX..xX..xX..x",
              HiHat = "x.x.x.x.x.x.x.x.")
        Song(name = "Latin: Bossa Nova", bpm = 130, patterns = [g])
    end,

    "Latin: Samba" => function ()
        g = P(HiHat   = "xxxXxxxXxxxXxxxX",
              Rim     = "X..X..X...X..X..",
              Kick    = "X..xX..xX..xX..x",
              HHPedal = "....x.......x...")
        Song(name = "Latin: Samba", bpm = 100, patterns = [g])
    end,

    "Latin: Afro 6/8" => function ()
        g = P(RideBell = "X.X.XX.X.X.X",
              Kick     = "X.....X.....",
              HHPedal  = "...x.....x..",
              Rim      = "......x..x..")
        Song(name = "Latin: Afro 6/8", bpm = 100, steps_per_beat = 3, patterns = [g])
    end,

    "Reggae: One Drop" => function ()
        g = P(Kick  = "........X.......",
              Rim   = "........X.......",
              HiHat = "x.o.x.o.x.o.x.o.")
        Song(name = "Reggae: One Drop", bpm = 75, swing = 0.6, patterns = [g])
    end,

    "Reggae: Rockers" => function ()
        g = P(Kick  = "X...X...X...X...",
              Rim   = "....X.......X...",
              HiHat = "x.o.x.o.x.o.x.o.")
        Song(name = "Reggae: Rockers", bpm = 80, swing = 0.6, patterns = [g])
    end,

    # ------------------------------------------------------------------ Hip-Hop / R&B
    "Hip-Hop: Boom Bap" => function ()
        g = P(HiHat = "x.x.x.x.x.x.x.x.",
              Snare = "....X.......X...",
              Kick  = "X......X.XX.....")
        Song(name = "Hip-Hop: Boom Bap", bpm = 90, swing = 0.58, patterns = [g])
    end,

    "R&B: Neo Soul" => function ()
        g = P(HiHat = "xoxoxoxoxoxoxoxo",
              Snare = "....X..o....X...",
              Kick  = "X..X......X..x..")
        Song(name = "R&B: Neo Soul", bpm = 72, swing = 0.62, patterns = [g])
    end,

    # ------------------------------------------------------------------ Taktarten
    "Taktart: Walzer 3/4" => function ()
        g = P(Kick  = "X...........",
              Snare = "....x...x...",
              HiHat = "x.x.x.x.x.x.")
        Song(name = "Taktart: Walzer 3/4", bpm = 120, patterns = [g])
    end,

    "Taktart: 6/8 Ballade" => function ()
        g = P(HiHat = "xxxxxx",
              Kick  = "X.....",
              Snare = "...X..")
        Song(name = "Taktart: 6/8 Ballade", bpm = 60, steps_per_beat = 3, patterns = [g])
    end,

    "Taktart: 5/4" => function ()
        g = P(HiHat = "x.x.x.x.x.x.x.x.x.x.",
              Snare = "....X.......X.......",
              Kick  = "X.......X.......X...")
        Song(name = "Taktart: 5/4", bpm = 110, patterns = [g])
    end,

    "Taktart: 7/8 (2+2+3)" => function ()
        g = P(HiHat = "x.x.x.x.x.x.x.",
              Snare = "..X...X.....X.",
              Kick  = "X...X...X.....")
        Song(name = "Taktart: 7/8 (2+2+3)", bpm = 120, patterns = [g])
    end,
]

const PRESET_NAMES = first.(PRESETS)

function preset(name::AbstractString)
    k = findfirst(p -> p.first == name, PRESETS)
    k === nothing && error("Unbekanntes Preset \"$name\". Verfügbar: $(join(PRESET_NAMES, ", "))")
    return PRESETS[k].second()
end
