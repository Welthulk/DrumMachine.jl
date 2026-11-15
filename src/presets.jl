# Groove library for practice. Each preset is a function that returns a fresh `Song`.
#
# Grid symbols:   . = off   o = ghost   x = normal   X = accent
# Tracks:         Kick Snare Rim HiHat HHOpen HHPedal Tom FloorTom Ride RideBell Crash
#
# 16th grid (steps_per_beat = 4), position in the bar:
#   1 e + a 2 e + a 3 e + a 4 e + a
#   1 2 3 4 5 6 7 8 9 ...          (step number)

function P(; steps = nothing, kw...)
    rows = Dict(String(k) => v for (k, v) in kw)
    lens = unique(length.(values(rows)))
    length(lens) == 1 || error(L("Preset-Zeilen unterschiedlich lang: {1}", Dict(k => length(v) for (k, v) in rows)))
    return pattern_from_rows(rows; steps)
end

"Copy of `p` with a crash on the one (hi-hat/ride on the one is dropped)."
function with_crash(p::Pattern)
    q = copy(p)
    for id in ("HiHat", "HHOpen", "Ride", "RideBell")
        q.grid[track_index(id), 1] = 0x00
    end
    q.grid[track_index("Crash"), 1] = 0x03
    return q
end

"Chain: crash bar, (n-2)× groove, fill  →  patterns [crash, groove, fill]."
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
        # Garibaldi-like: 16th hi-hat with accents on the quarters, open hi-hat on the 4+,
        # ghost notes between bass drum and backbeat.
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
        # Approximation of the Garibaldi groove: fast 16th funk tempo, syncopated bass drum,
        # ghost notes between the backbeats, open hi-hat on the 4+ (variation also on the 2+).
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
        # Linear in Tower of Power style: exactly one instrument on every 16th,
        # open hi-hat on the 4+ as the climax before the one.
        #             1 e + a 2 e + a 3 e + a 4 e + a
        g = P(Kick   = "X.....X.X..X...x",
              Snare  = "..o.X....o..X...",
              HiHat  = ".x.x.x.x..x..x..",
              HHOpen = "..............X.")
        Song(name = "Funk: Garibaldi Linear (Oakland)", bpm = 100, patterns = [g])
    end,

    "Funk: Oakland Half-Time" => function ()
        # Half-time funk: backbeat only on the 3, steady 16th hi-hat with quarter-note accents,
        # ghost notes and syncopated bass drum.
        g = P(HiHat = "XxxxXxxxXxxxXxx.",
              HHOpen = "...............X",
              Snare = ".o..o...X.o..o..",
              Kick  = "X.x.....x..x.x..")
        Song(name = "Funk: Oakland Half-Time", bpm = 92, patterns = [g])
    end,

    "Funk: Linear" => function ()
        # Linear: never two instruments at the same time.
        g = P(Kick  = "X..x...x.x....x.",
              Snare = "....X.o....oX...",
              HiHat = ".xx..x..x.x..x.x")
        Song(name = "Funk: Linear", bpm = 96, patterns = [g])
    end,

    "Funk: 16tel Zwei-Hand-Hihat" => function ()
        # Hi-hat with both hands, the snare replaces the hi-hat on the backbeat.
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
    # Triplet grids: the swing control shifts the third triplet (67 % = exact, 75 % = dotted).
    # Straight grids: the swing control shifts the "+" (on 8ths) or "e"/"a" (on 16ths).

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
        # The snare plays the shuffle throughout (ghost notes + backbeat), ride on the quarters.
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
        # 16th triplets (6 per beat): hi-hat shuffle, ghost notes on the middle triplets,
        # backbeat only on the 3.
        g = P(HiHat = "x.xx.xx.xx.xx.xx.xx.xx.x",
              Snare = ".o..o..o..o.X...o..o..o.",
              Kick  = "X..........x.........x..")
        Song(name = "Shuffle: Purdie Half-Time (16tel-Triolen)", bpm = 80, steps_per_beat = 6, patterns = [g])
    end,

    "Shuffle: Rosanna-Stil (Porcaro/Purdie)" => function ()
        # Porcaro's take on the Purdie shuffle: 16th triplets, hi-hat shuffle with accent on the 3,
        # ghost notes on the middle triplets, backbeat only on the 3,
        # bass drum pickups before the 3 and before the 1.
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
        # Basic groove in the style of "Everybody Wants to Rule the World", 12/8:
        # 8th triplets, 4 dotted quarters per bar, dotted quarter = 112.
        # Hi-hat on every second triplet (6 against 4), kick and snare together on 2 and 4.
        # Pattern 1 = basic groove, pattern 2 = transition with snare double and open hi-hat.
        #             1 + a 2 + a 3 + a 4 + a
        g = P(HiHat  = ".x.x.x.x.x.x",
              Snare  = "...X.....X..",
              Kick   = "X.xX..X.xX..")
        u = P(HiHat  = ".x.x.x.x....",
              HHOpen = "...........x",
              Snare  = "...X.....Xx.",
              Kick   = "X.xX..X.xX..")
        Song(name = "Shuffle: Rule-the-World-Stil (Tears for Fears, 12/8)", bpm = 112, steps_per_beat = 3,
             patterns = [g, u], chain = [1, 1, 1, 1, 1, 1, 1, 2])
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
        # 16th grid, swing 66 % on 8ths: the "+" slides onto the third triplet.
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

    "Jazz: Double-Time Swing (Whiplash-Stil)" => function ()
        # Very fast swing (quarter = 300+): ride with skip notes on the "+" of 2 and 4, hi-hat
        # pedal on 2 and 4, feathered bass drum. 16th grid so the fill can run in 16ths; at this
        # tempo the swing is almost straight (58 %).
        g = P(Ride    = "x...X.x.x...X.x.",
              HHPedal = "....x.......x...",
              Kick    = "o...o...o...o...")
        c = P(Ride    = "x...X.x.x...X.x.",
              HHPedal = "....x.......x...",
              Snare   = "......o.......x.",
              Kick    = "o...o...o.X.o...")
        f = P(Ride    = "x...X...........",
              HHPedal = "....x...........",
              Snare   = "........XxxxX...",
              Tom     = ".............x..",
              FloorTom = "..............xx",
              Kick    = "o...o...........")
        Song(name = "Jazz: Double-Time Swing (Whiplash-Stil)", bpm = 300, swing = 0.58, swing_on = 8,
             patterns = [with_crash(g), g, c, f], chain = [1, 2, 3, 2, 2, 3, 2, 4], fx = "Room", fxmix = 0.3)
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

    # ------------------------------------------------------------------ Time signatures
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
    k === nothing && error(L("Unbekanntes Preset \"{1}\". Verfügbar: {2}", name, join(PRESET_NAMES, ", ")))
    return PRESETS[k].second()
end
