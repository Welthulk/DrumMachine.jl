# Fill generator: replaces the last beats of a pattern with a fill.
#
# For the fill span (n steps, spb steps per beat) each style returns a list of
# (step within the span, track ID, level). Everything else in the span is cleared,
# the groove before it is kept. Works with any grid (16ths, triplets, 8ths). The span always
# starts on a beat of the bar, so beatstart(i, spb) within the span matches the bar's beats.

const _O, _N, _A = 0x01, 0x02, 0x03      # ghost note, normal, accent

beatstart(i, spb) = (i - 1) % spb == 0

"Snare on every step, accent at the end."
function fill_wirbel(n, spb)
    hits = [(i, "Snare", i == n ? _A : beatstart(i, spb) ? _A : _N) for i in 1:n]
    push!(hits, (1, "Kick", _N))
    hits
end

"Snare → tom 1 → tom 2 → floor tom, spread evenly across the span."
function fill_abgang(n, spb)
    drums = ("Snare", "Tom", "Tom2", "FloorTom")
    hits = [(i, drums[cld(4i, n)], beatstart(i, spb) ? _A : _N) for i in 1:n]
    push!(hits, (n, "Kick", _N))
    hits
end

"First beat snare, then alternating tom and floor tom, bass drum on the beats."
function fill_wechsel(n, spb)
    hits = Tuple{Int,String,UInt8}[]
    for i in 1:n
        d = i <= spb ? "Snare" : isodd(i) ? "Tom" : "FloorTom"
        push!(hits, (i, d, beatstart(i, spb) ? _A : _N))
        beatstart(i, spb) && push!(hits, (i, "Kick", _N))
    end
    hits
end

"Snare and floor tom in unison every 3 steps (3-3-2 feel), plus bass drum."
function fill_akzente(n, _)
    hits = Tuple{Int,String,UInt8}[]
    for i in 1:3:n
        append!(hits, [(i, "Snare", _A), (i, "FloorTom", _A), (i, "Kick", _N)])
    end
    hits
end

"Snare crescendo: ghost notes, then normal, accents at the end; floor tom on the last step."
function fill_crescendo(n, _)
    lv(i) = i <= n ÷ 3 ? _O : i <= 2n ÷ 3 ? _N : _A
    hits = [(i, "Snare", lv(i)) for i in 1:n]
    append!(hits, [(n, "FloorTom", _A), (n, "Kick", _N)])
    hits
end

"""
Full bar around the kit, one drum per beat: snare, tom 1, tom 2, floor tom (with 4 beats or more,
spread evenly); with fewer beats snare, then tom 1, floor tom on the last beat. Bass drum on the beats.
"""
function fill_rundlauf(n, spb)
    nb = cld(n, spb)
    drums = ("Snare", "Tom", "Tom2", "FloorTom")
    hits = Tuple{Int,String,UInt8}[]
    for i in 1:n
        b = cld(i, spb)                         # beat within the span
        d = nb >= 4 ? drums[cld(4b, nb)] : b <= nb ÷ 2 ? "Snare" : b < nb ? "Tom" : "FloorTom"
        push!(hits, (i, d, beatstart(i, spb) ? _A : _N))
        beatstart(i, spb) && push!(hits, (i, "Kick", _N))
    end
    hits
end

"Fill styles: (name, length in beats, generator)."
const FILL_STYLES = [
    ("Snare-Wirbel",          1, fill_wirbel),
    ("Tom-Abgang",            1, fill_abgang),
    ("Snare/Tom-Wechsel",     2, fill_wechsel),
    ("Akzente 3-3-2",         2, fill_akzente),
    ("Snare-Crescendo",       2, fill_crescendo),
    ("Tom-Abgang (2 Schläge)", 2, fill_abgang),   # i18n-ok: names translated at display
    ("Ganzer Takt",           4, fill_rundlauf),   # i18n-ok: names translated at display
]

"""
    make_fill(p, steps_per_beat, style = 1) -> Pattern

Copy of `p` whose last beats are replaced by the fill `FILL_STYLES[style]`
(the style is chosen cyclically, so any integer is allowed). The fill span starts on a beat;
in a bar with a partial last beat (e.g. 7/8 with 14 steps) it also covers that partial beat.
"""
function make_fill(p::Pattern, spb::Int, style::Integer = 1)
    _, beats, gen = FILL_STYLES[mod1(style, length(FILL_STYLES))]
    off = max(0, fld(p.steps - beats * spb, spb) * spb)   # span starts on a beat of the bar
    n = p.steps - off
    q = copy(p)
    q.grid[:, off+1:p.steps] .= 0x00
    q.orn[:, off+1:p.steps] .= 0x00
    for (i, id, lv) in gen(n, spb)
        q.grid[track_index(id), off+i] = lv
    end
    return q
end

fill_name(style::Integer) = FILL_STYLES[mod1(style, length(FILL_STYLES))][1]
