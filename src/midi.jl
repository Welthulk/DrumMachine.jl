# MIDI input for recording from an e-drum kit: a thin PortMidi wrapper (PortMidi_jll), the note
# map (Roland TD-27, General MIDI) and the pure functions that turn a hit into a grid cell. Also
# the MIDI output of the setup player (MIDI files) and of the main window (`SeqOut`: the
# sequencer plays a drum module instead of the kit).
#
# Threads: a reader task polls the open input about every 1 ms and hands note-ons through a
# Channel to the GUI, which writes them into the pattern on the main thread. The setup player
# and the sequencer send their notes from the audio thread. PortMidi is not thread-safe: every
# PortMidi call holds the spin lock PM_LOCK, only for that one call; the audio thread only tries
# it and sends later if it is taken, so it never waits. Opening, closing and listing devices also
# hold MIDI_LOCK, so that PortMidi is not re-initialised in between.
# For the timing the audio thread logs, per block, its position with `time_ns()` and the start of
# every bar (`HitClock`, under `eng.lock`).

import PortMidi_jll

# ---------------------------------------------------------------------------
# Note map, velocity
# ---------------------------------------------------------------------------

"Roland TD-27 factory note numbers (heads, rims, edges) -> track id."
const TD27_NOTES = Dict(
    36 => "Kick",
    38 => "Snare", 40 => "Snare",                    # head, rim
    37 => "Rim",                                     # cross stick
    48 => "Tom", 50 => "Tom",                        # tom 1, head and rim
    45 => "Tom2", 47 => "Tom2",                      # tom 2
    43 => "FloorTom", 58 => "FloorTom",              # tom 3
    46 => "HHOpen", 26 => "HHOpen",                  # hi-hat open bow, edge
    42 => "HiHat", 22 => "HiHat",                    # hi-hat closed bow, edge
    44 => "HHPedal",
    49 => "Crash", 55 => "Crash", 57 => "Crash", 52 => "Crash",   # crash 1 and 2, bow and edge
    51 => "Ride", 59 => "Ride",                      # ride bow, edge
    53 => "RideBell",
)
"General MIDI drum notes not covered by the TD-27 table."
const GM_NOTES = Dict(35 => "Kick", 39 => "Snare", 41 => "FloorTom")

"""
Settings for MIDI recording: note -> track index, velocity thresholds (below `ghost` = ghost
note, from `accent` on = accent), the thresholds per track (`levels[t]`, the defaults unless set
in `[midi_levels]`) and the user offset in ms (positive = hits count earlier).
"""
struct MidiConfig
    map::Dict{Int,Int}
    ghost::Int
    accent::Int
    offset_ms::Float64
    levels::Vector{Tuple{Int,Int}}
end

"""
    midi_note_map(settings) -> Dict{Int,Int}

Note number -> track index: the TD-27 table, General MIDI as fallback, then the settings table
`[midi_map]` ("note" = "TrackId") on top. A value that is no track id (e.g. "off") removes the note.
"""
function midi_note_map(settings::AbstractDict = load_settings())
    m = Dict{Int,Int}()
    for tab in (GM_NOTES, TD27_NOTES), (n, id) in tab
        m[n] = track_index(id)
    end
    user = get(settings, "midi_map", nothing)
    user isa AbstractDict || return m
    for (k, v) in user
        n = tryparse(Int, string(k))
        (n === nothing || !(0 <= n <= 127)) && continue
        t = track_index(string(v))
        t === nothing ? delete!(m, n) : (m[n] = t)
    end
    return m
end

_setting(d, key, default, lo, hi) = (v = get(d, key, default); v isa Real ? clamp(v, lo, hi) : default)

"""
    midi_levels(settings, ghost, accent) -> Vector{Tuple{Int,Int}}

(ghost, accent) per track: the table `[midi_levels]` (`TrackId = [ghost, accent]`, e.g. set by
*Einmessen*), the defaults `ghost`/`accent` for tracks not in it or with an invalid entry.
"""
function midi_levels(settings::AbstractDict, ghost::Int, accent::Int)
    lv = fill((ghost, accent), NTRACKS)
    tab = get(settings, "midi_levels", nothing)
    tab isa AbstractDict || return lv
    for (id, v) in tab
        t = track_index(string(id))
        (t === nothing || !(v isa AbstractVector) || length(v) != 2 || !all(x -> x isa Real, v)) && continue
        g, a = round(Int, clamp(v[1], 1, 127)), round(Int, clamp(v[2], 1, 128))
        g < a && (lv[t] = (g, a))
    end
    return lv
end

"MIDI settings from the settings file: `midi_map`, `midi_ghost`, `midi_accent`, `midi_offset_ms`, `midi_levels`."
function midi_config(settings::AbstractDict = load_settings())
    g = round(Int, _setting(settings, "midi_ghost", 45, 1, 127))
    a = round(Int, _setting(settings, "midi_accent", 105, 1, 128))
    return MidiConfig(midi_note_map(settings), g, a, Float64(_setting(settings, "midi_offset_ms", 0, -500, 500)),
                      midi_levels(settings, g, a))
end

"Grid level of a hit: 1 (ghost) below `ghost`, 3 (accent) from `accent` on, else 2."
velocity_level(v::Integer, ghost::Integer, accent::Integer) = v >= accent ? 3 : v < ghost ? 1 : 2
"Grid level of a hit on track `t`, with the thresholds of that track."
velocity_level(v::Integer, c::MidiConfig, t::Integer) = velocity_level(v, c.levels[t]...)

# ---------------------------------------------------------------------------
# Calibration ("Einmessen"): the player plays the pattern shown, each hit is compared with the
# level programmed in its cell, and the thresholds per track follow from that
# ---------------------------------------------------------------------------

"Hits needed on a track before its thresholds are changed, and per level for a boundary."
const CAL_MIN_HITS = 8
const CAL_MIN_LEVEL = 3
"Largest distance (ms) of a hit from the typical timing that still counts for the thresholds."
const CAL_MAX_MS = 50
"Hits needed for a new timing offset, and the smallest change (ms) that is written."
const CAL_MIN_TIMING = 16
const CAL_MIN_SHIFT = 3.0

"""
    calibrate(hits, cfg) -> (levels, offset_ms, median_ms)

Evaluates a calibration take. `hits` are `(track, velocity, programmed level, ms from the step)`.
`median_ms` is the typical distance of the hits from their steps (positive = late): with at least
`CAL_MIN_TIMING` hits and a distance of `CAL_MIN_SHIFT` ms or more, `offset_ms` is the corrected
`midi_offset_ms` (else `nothing`). The thresholds (see [`calibrate_levels`](@ref)) use only hits
within `CAL_MAX_MS` of the typical timing, so stray hits do not count.
"""
function calibrate(hits::AbstractVector, cfg::MidiConfig)
    isempty(hits) && return Dict{Int,Tuple{Int,Int}}(), nothing, 0.0
    med = Float64(_median([Float64(h[4]) for h in hits]))
    near = [h for h in hits if abs(h[4] - med) <= CAL_MAX_MS]
    off = length(hits) >= CAL_MIN_TIMING && abs(med) >= CAL_MIN_SHIFT ?
          clamp(round(cfg.offset_ms + med; digits = 1), -500.0, 500.0) : nothing
    lv = calibrate_levels(near, cfg)
    hh, ho = track_index("HiHat"), track_index("HHOpen")      # one cymbal: the other track as well
    haskey(lv, hh) && !haskey(lv, ho) && (lv[ho] = lv[hh])
    haskey(lv, ho) && !haskey(lv, hh) && (lv[hh] = lv[ho])
    return lv, off, med
end

# ---------------------------------------------------------------------------
# A calibration take: waiting for the first hit, warm-up, measuring; ends after a pause
# ---------------------------------------------------------------------------

"Bars after the first hit that are not measured (time to get into the groove)."
const CAL_WARMUP_BARS = 8
"Pause in seconds that ends the measurement, and the longest wait for the first hit."
const CAL_IDLE_S = 6.0
const CAL_WAIT_S = 180.0

"Hit of a take: track, velocity, programmed level, ms from the step, measured (not warm-up)."
const CalHit = @NamedTuple{track::Int, vel::Int, level::Int, ms::Float64, measured::Bool}

"""
State of a calibration take. Times are `time()` seconds; `warmup` is the length of the warm-up
after the first hit. See [`cal_phase`](@ref), [`cal_add!`](@ref), [`cal_end_reason`](@ref).
"""
mutable struct CalTake
    t_start::Float64
    t_first::Float64          # first hit, 0 = none yet
    t_last::Float64           # last hit
    warmup::Float64
    hits::Vector{CalHit}
end
CalTake(now::Real, warmup::Real) = CalTake(now, 0.0, 0.0, warmup, CalHit[])

"Phase of the take at time `now`: `:wait` (no hit yet), `:warmup` or `:measure`."
cal_phase(c::CalTake, now::Real) = c.t_first == 0 ? :wait : now < c.t_first + c.warmup ? :warmup : :measure

"Adds a hit at time `now` (track, velocity, programmed level, ms from the step)."
function cal_add!(c::CalTake, now::Real, track::Int, vel::Int, level::Int, ms::Real)
    c.t_first == 0 && (c.t_first = now)
    c.t_last = now
    push!(c.hits, (track = track, vel = vel, level = level, ms = Float64(ms), measured = cal_phase(c, now) == :measure))
    return c
end

"Hits measured after the warm-up."
cal_measured(c::CalTake) = [h for h in c.hits if h.measured]

"""
    cal_end_reason(c, now) -> Symbol or nothing

`:pause` when the measurement runs and nothing was played for `CAL_IDLE_S` seconds, `:timeout`
when no hit came within `CAL_WAIT_S` seconds, else `nothing`.
"""
function cal_end_reason(c::CalTake, now::Real)
    c.t_first == 0 && return now - c.t_start > CAL_WAIT_S ? :timeout : nothing
    cal_phase(c, now) == :measure && now - max(c.t_last, c.t_first + c.warmup) > CAL_IDLE_S && return :pause
    return nothing
end

"Seconds of one bar of pattern `p` in `song` (own pattern tempo counts)."
bar_seconds(song::Song, p::Pattern) = p.steps / song.steps_per_beat * 60 / pattern_bpm(song, p)

"""
Result of a take: the measured hits, the configuration before, the new thresholds per track, the
new `midi_offset_ms` (`nothing` = unchanged) and the typical timing in ms.
"""
struct CalResult
    hits::Vector{CalHit}
    before::MidiConfig
    levels::Dict{Int,Tuple{Int,Int}}
    offset::Union{Nothing,Float64}
    median_ms::Float64
end

"Evaluates the measured hits of a take with the configuration `cfg` (see [`calibrate`](@ref))."
function cal_result(c::CalTake, cfg::MidiConfig)
    hs = cal_measured(c)
    lv, off, med = calibrate([(h.track, h.vel, h.level, h.ms) for h in hs], cfg)
    return CalResult(hs, cfg, lv, off, med)
end

"Share of the hits on track `t` that get their programmed level with thresholds `(ghost, accent)`."
function cal_hit_rate(hs::AbstractVector{CalHit}, t::Int, th::Tuple{Int,Int})
    ts = [h for h in hs if h.track == t]
    isempty(ts) && return 0.0
    return count(h -> velocity_level(h.vel, th...) == h.level, ts) / length(ts)
end

# ---------------------------------------------------------------------------
# Recording into a new song: a click plays, the take starts with the first hit; every bar played
# becomes a pattern (equal bars share one), the chain follows the order. Ends after a pause.
# ---------------------------------------------------------------------------

"Pause in seconds that ends a recording."
const REC_IDLE_S = 8.0
"Most different patterns of a recording (the pattern buttons of the main window)."
const REC_MAX_PATTERNS = 24

"A recorded hit: bar (0 = the bar the click started with), step (1-based), track, level, velocity, ms off the step."
const RecHit = @NamedTuple{bar::Int, step::Int, track::Int, level::Int, vel::Int, ms::Float64}

"""
State of a recording: tempo and grid (no swing, so every step has the same length), the engine
position `t0` of step 1 of the first click bar, times (`time()`) of start, first and last hit,
the length in bars (`maxbars`, 0 = until a pause) and the bar of the first hit (`bar0`).
"""
mutable struct RecTake
    bpm::Float64
    spb::Int
    steps::Int
    t0::Float64
    steplen::Float64
    t_start::Float64
    t_first::Float64
    t_last::Float64
    maxbars::Int
    bar0::Int
    hits::Vector{RecHit}
end
RecTake(bpm::Real, spb::Int, steps::Int, t0::Real, now::Real; maxbars::Int = 0) =
    RecTake(Float64(bpm), spb, steps, Float64(t0), 60 / bpm / spb * SR, Float64(now), 0.0, 0.0, maxbars, 0, RecHit[])

"Bar (0-based), step (1-based) and ms off the nearest step for the engine position `h` (samples)."
function rec_cell(r::RecTake, h::Real)
    g = round(Int, (h - r.t0) / r.steplen)
    return fld(g, r.steps), mod(g, r.steps) + 1, 1000 * (h - r.t0 - g * r.steplen) / SR
end

"""
Adds a hit heard at engine position `h`. Ignored (`nothing`): hits before the first click bar and,
with a fixed length, after the last bar.
"""
function rec_add!(r::RecTake, now::Real, h::Real, track::Int, vel::Int, level::Int)
    bar, step, ms = rec_cell(r, h)
    bar < 0 && return nothing
    r.t_first > 0 && r.maxbars > 0 && bar >= r.bar0 + r.maxbars && return nothing
    r.t_first == 0 && (r.t_first = now; r.bar0 = bar)
    r.t_last = now
    hit = (bar = bar, step = step, track = track, level = level, vel = vel, ms = ms)
    push!(r.hits, hit)
    return hit
end

"Phase of a recording: `:wait` (click plays, no hit yet) or `:rec`."
rec_phase(r::RecTake) = r.t_first == 0 ? :wait : :rec

"""
    rec_end_reason(r, now, h = nothing) -> Symbol or nothing

`:done` when a fixed length is reached (`h` = engine position heard now), `:pause` after
`REC_IDLE_S` s without a hit (only without a fixed length), `:timeout` without any hit for
`CAL_WAIT_S` s, else `nothing`.
"""
function rec_end_reason(r::RecTake, now::Real, h::Union{Real,Nothing} = nothing)
    r.t_first == 0 && return now - r.t_start > CAL_WAIT_S ? :timeout : nothing
    if r.maxbars > 0
        return h !== nothing && rec_cell(r, h)[1] >= r.bar0 + r.maxbars ? :done : nothing
    end
    return now - r.t_last > REC_IDLE_S ? :pause : nothing
end

"Bars recorded so far: from the first hit to the last (0 without hits)."
rec_bars(r::RecTake) = isempty(r.hits) ? 0 : maximum(h.bar for h in r.hits) - r.bar0 + 1

"""
    rec_song(r; name, kit, maxpat = REC_MAX_PATTERNS) -> (song, info)

The recording as a song: one bar per chain entry from the bar of the first hit to the bar of the
last; equal bars share a pattern. Two hits of a track on one step keep the louder level. With more
than `maxpat` different bars the others take the most similar pattern (`info.merged`). `info`:
bars, patterns, merged, hits, typical timing in ms.
"""
function rec_song(r::RecTake; name::AbstractString, kit::AbstractString, maxpat::Int = REC_MAX_PATTERNS)
    isempty(r.hits) && error("no hits recorded")
    b0 = r.bar0
    b1 = r.maxbars > 0 ? b0 + r.maxbars - 1 : maximum(h.bar for h in r.hits)   # fixed length: all bars
    grids = [zeros(UInt8, NTRACKS, MAXSTEPS) for _ in b0:b1]
    for h in r.hits
        g = grids[h.bar-b0+1]
        g[h.track, h.step] = max(g[h.track, h.step], UInt8(h.level))
    end
    pats = Pattern[]; chain = Int[]; merged = 0
    for g in grids
        k = findfirst(p -> p.grid == g, pats)
        if k === nothing && length(pats) < maxpat
            push!(pats, Pattern(r.steps, g)); k = length(pats)
        elseif k === nothing
            k = argmin([count(p.grid .!= g) for p in pats]); merged += 1
        end
        push!(chain, k)
    end
    song = Song(; name, bpm = r.bpm, steps_per_beat = r.spb, patterns = pats, chain, kit, countin = 1)
    info = (bars = length(grids), patterns = length(pats), merged, hits = length(r.hits),
            median_ms = Float64(_median([h.ms for h in r.hits])))
    return song, info
end

"""
    cal_target(p, t, s) -> (track, level) or nothing

Track and programmed level a calibration hit on track `t` at step `s` of pattern `p` counts for.
Closed and open hi-hat are one cymbal: a module sends "open" when the pedal is not quite closed,
so a hit on the other hi-hat track counts where the pattern has a hi-hat.
"""
function cal_target(p::Pattern, t::Int, s::Int)
    lv = Int(p.grid[t, s])
    lv > 0 && return (t, lv)
    hh, ho = track_index("HiHat"), track_index("HHOpen")
    o = t == ho ? hh : t == hh ? ho : 0
    o > 0 && p.grid[o, s] > 0 && return (o, Int(p.grid[o, s]))
    return nothing
end

"Value at fraction `q` (0..1) of the sorted vector `v` (nearest rank)."
_quantile(v::Vector{Int}, q::Real) = v[clamp(round(Int, q * (length(v) - 1)) + 1, 1, length(v))]

"""
    level_boundary(lo, hi) -> Int

Velocity threshold between two levels: the value from which on a hit counts as the louder level,
with the fewest hits of `lo` (softer) and `hi` (louder) on the wrong side. Among equally good
values the one nearest to the middle between the two medians.
"""
function level_boundary(lo::Vector{Int}, hi::Vector{Int})
    lo, hi = sort(lo), sort(hi)
    mid = (_median(lo) + _median(hi)) / 2
    best, berr, bd = 64, typemax(Int), Inf
    for x in 2:127
        err = count(>=(x), lo) + count(<(x), hi)
        d = abs(x - 0.5 - mid)
        (err < berr || (err == berr && d < bd)) && ((best, berr, bd) = (x, err, d))
    end
    return best
end

"""
    calibrate_levels(hits, cfg) -> Dict{Int,Tuple{Int,Int}}

New (ghost, accent) for each track with at least `CAL_MIN_HITS` hits. `hits` are
`(track, velocity, programmed level)`. A boundary between two levels played at least
`CAL_MIN_LEVEL` times each is set from the hits (see [`level_boundary`](@ref)). Without the softer
or louder level, the threshold moves only so far that 98 % of the hits played keep their level.
"""
function calibrate_levels(hits::AbstractVector, cfg::MidiConfig)
    out = Dict{Int,Tuple{Int,Int}}()
    for t in 1:NTRACKS
        vs = [Int[h[2] for h in hits if h[1] == t && h[3] == l] for l in 1:3]
        sum(length, vs) >= CAL_MIN_HITS || continue
        ok = [length(v) >= CAL_MIN_LEVEL for v in vs]
        any(ok) || continue
        g, a = cfg.levels[t]
        if ok[1] && (ok[2] || ok[3])
            g = level_boundary(vs[1], ok[2] ? vs[2] : vs[3])
        elseif !ok[1] && !(isempty(vs[2]) && isempty(vs[3]))
            g = min(g, _quantile(sort(vcat(vs[2], vs[3])), 0.02))
        end
        if ok[3] && (ok[2] || ok[1])
            a = level_boundary(ok[2] ? vs[2] : vs[1], vs[3])
        elseif !ok[3] && !(isempty(vs[1]) && isempty(vs[2]))
            a = max(a, _quantile(sort(vcat(vs[1], vs[2])), 0.98) + 1)
        end
        g, a = clamp(g, 1, 127), clamp(a, 2, 128)
        g >= a && (g = a - 1)
        out[t] = (g, a)
    end
    return out
end

"""
    save_midi_levels!(new) -> MidiConfig

Writes the thresholds `new` (track => (ghost, accent)) into the table `[midi_levels]` of the
settings file, keeps the entries of the other tracks, and returns the new configuration.
"""
function save_midi_levels!(new::AbstractDict)
    tab = get(load_settings(), "midi_levels", nothing)
    tab = tab isa AbstractDict ? Dict{String,Any}(string(k) => v for (k, v) in tab) : Dict{String,Any}()
    for (t, (g, a)) in new
        tab[TRACK_IDS[t]] = [g, a]
    end
    return midi_config(save_setting!("midi_levels", tab))
end

# ---------------------------------------------------------------------------
# Timing: engine position at a given time, grid cell of a hit
# ---------------------------------------------------------------------------

"Start of a bar as played by the engine: sample time, position in the sequence, pattern (0 = count-in)."
struct BarMark
    start::Float64
    seqpos::Int
    pat::Int
end

"Start of a step as scheduled by the engine: sample time, step index (0-based)."
struct StepMark
    start::Float64
    step::Int
end

const CLOCK_LEN = 64      # audio blocks kept (~0.7 s)
const BARS_LEN = 8
const STEPS_LEN = 128

"""
Timing log of the engine for MIDI recording, written by the audio thread under `eng.lock`:
engine position at the start of each audio block with its `time_ns()`, the starts of the last
bars and steps, and the output latency of the stream.
"""
mutable struct HitClock
    t::Vector{UInt64}
    pos::Vector{Int}
    n::Int
    bars::Vector{BarMark}
    nb::Int
    steps::Vector{StepMark}
    ns::Int
    latency::Float64              # s, from rendering a block to hearing it (without the block itself)
end
HitClock() = HitClock(zeros(UInt64, CLOCK_LEN), zeros(Int, CLOCK_LEN), 0, fill(BarMark(0.0, 0, 0), BARS_LEN), 0,
                      fill(StepMark(0.0, 0), STEPS_LEN), 0, 0.0)

"Logs the engine position `pos` at time `t` (start of an audio block). No allocation."
function log_block!(c::HitClock, t::UInt64, pos::Int)
    i = c.n % CLOCK_LEN + 1
    @inbounds c.t[i] = t; c.pos[i] = pos
    c.n += 1
    return nothing
end

"Logs the start of a bar. No allocation."
function log_bar!(c::HitClock, start::Float64, seqpos::Int, pat::Int)
    @inbounds c.bars[c.nb % BARS_LEN + 1] = BarMark(start, seqpos, pat)
    c.nb += 1
    return nothing
end

"Logs the start of step `s` (0-based). No allocation."
function log_step!(c::HitClock, start::Float64, s::Int)
    @inbounds c.steps[c.ns % STEPS_LEN + 1] = StepMark(start, s)
    c.ns += 1
    return nothing
end

"Oldest first: the logged entries of ring `v` with `n` writes so far."
ring_order(v::Vector, n::Int) = n <= length(v) ? v[1:n] : vcat(v[n%length(v)+1:end], v[1:n%length(v)])

"Copy of the log (take `eng.lock` around it): block times, positions, bar starts, latency, step starts."
clock_snapshot(c::HitClock) = (ring_order(c.t, c.n), ring_order(c.pos, c.n), ring_order(c.bars, c.nb), c.latency,
                               ring_order(c.steps, c.ns))

"""
    heard_sample(ts, pos, t, delay) -> Float64 or nothing

Engine position (samples) that could be heard at time `t` (`time_ns()`). `ts`/`pos` are the logged
block starts. Each block gives the position at `t` by counting on at the sample rate from its own
start; the median of these values is used, because the audio thread renders in bursts (the sound
server takes several blocks at once) and single block times jitter by about one block. `delay` (s)
is the time from rendering to hearing (output latency, one block, user offset) and is subtracted.
"""
function heard_sample(ts::AbstractVector{<:Integer}, pos::AbstractVector{<:Integer}, t::Integer, delay::Real)
    isempty(ts) && return nothing
    est = sort!([pos[k] + Float64(Int64(t) - Int64(ts[k])) / 1e9 * SR for k in eachindex(ts, pos)])
    n = length(est)
    mid = isodd(n) ? est[(n+1)÷2] : (est[n÷2] + est[n÷2+1]) / 2
    return mid - delay * SR
end

"Rendering-to-hearing delay in s: output latency, one block, minus the user offset."
hit_delay(latency::Real, offset_ms::Real) = latency + BLOCK / SR + offset_ms / 1000

"Pattern index of a sequence entry: -1 = edit pattern, 0 = count-in."
seq_pattern(entry::Int, edit_pat::Int, npat::Int) = entry == -1 ? clamp(edit_pat, 1, npat) : entry == 0 ? 0 : clamp(entry, 1, npat)

"Pattern played in a bar of `pat` (0 = count-in: the first real pattern of the sequence)."
function bar_pattern(song::Song, seq::Vector{Int}, edit_pat::Int, pat::Int)
    n = length(song.patterns)
    if pat == 0
        k = findfirst(!=(0), seq)
        return song.patterns[k === nothing ? 1 : seq_pattern(seq[k], edit_pat, n)]
    end
    return 1 <= pat <= n ? song.patterns[pat] : nothing
end

"Start of step `s` logged in `[lo, hi)`, else `t`."
function logged_start(steps::AbstractVector{StepMark}, s::Int, lo::Real, hi::Real, t::Real)
    i = findlast(m -> m.step == s && lo <= m.start < hi, steps)
    return i === nothing ? t : steps[i].start
end

"""
    record_step(song, seq, loop_from, edit_pat, bars, h, steps = []) -> (pattern, step, off) or nothing

Grid cell for a hit heard at engine position `h` (samples): the nearest step of the bar playing
then, with the real step times (swing, pattern tempo, grid); `off` is the distance of the hit
from that step in samples (positive = late). A hit that rounds past the last step
goes to step 1 of the next bar played. In a count-in bar a hit counts only if it rounds to step 1
of the first real bar. `bars` are the logged bar starts, `steps` the logged step starts, oldest
first; step times not logged yet are computed from the pattern. `seq`, `loop_from` and
`edit_pat` as in the engine.
"""
function record_step(song::Song, seq::Vector{Int}, loop_from::Int, edit_pat::Int,
                     bars::AbstractVector{BarMark}, h::Real, steps::AbstractVector{StepMark} = StepMark[])
    k = findlast(b -> b.start <= h, bars)
    k === nothing && return nothing
    start, sp, pat = bars[k].start, bars[k].seqpos, bars[k].pat
    stop = k < length(bars) ? bars[k+1].start : Inf  # logged steps of this bar lie in [start, stop)
    logged = true                                    # later bars are not in the log
    npat = length(song.patterns)
    function next!()                              # move on to the bar after this one
        sp = sp < length(seq) ? sp + 1 : loop_from
        sp == 0 && return false                   # end of the sequence
        pat = seq_pattern(seq[sp], edit_pat, npat)
        return true
    end
    for _ in 1:4                                  # the log may lag behind by a bar or so
        p = bar_pattern(song, seq, edit_pat, pat)
        p === nothing && return nothing
        t = start; best = 1; bt = t
        for s in 0:p.steps-1                      # step starts; index p.steps+1 = next bar
            t += step_samples(song, s, p)
            if logged                             # as the engine timed it (the grid may change)
                t = s + 1 < p.steps ? logged_start(steps, s + 1, start, stop, t) : isfinite(stop) ? stop : t
            end
            abs(h - t) < abs(h - bt) && (best = s + 2; bt = t)
        end
        if h >= t                                 # beyond this bar: look at the next one
            start = t; logged = false
            next!() || return nothing
            continue
        end
        best <= p.steps && return pat == 0 ? nothing : (pat, best, h - bt)
        next!() || return nothing
        return pat == 0 ? nothing : (pat, 1, h - bt)
    end
    return nothing
end

"Starts the current edit pattern in a loop with one count-in bar (record pressed while stopped)."
record_play!(eng) = lock(() -> start_seq!(eng, [0, -1], 2), eng.lock)

# ---------------------------------------------------------------------------
# PortMidi
# ---------------------------------------------------------------------------

struct PmDeviceInfo
    structVersion::Cint
    interf::Cstring
    name::Cstring
    input::Cint
    output::Cint
    opened::Cint
    is_virtual::Cint
end

struct PmEvent
    message::Int32
    timestamp::Int32
end

const libpm = PortMidi_jll.libportmidi
const MIDI_LOCK = ReentrantLock()          # open, close, list devices (not in the audio thread)
const PM_LOCK = Threads.SpinLock()         # held around each single PortMidi call
const PM_READY = Ref(false)
const PM_OPEN = Ref(0)                     # open streams (in and out); PortMidi is only re-initialised without any
const PM_FILT = Int32(1 << 0x0E | 1 << 0x00 | 1 << 0x08)   # drop active sensing, sysex, clock
const MIDI_OUT_LATENCY = 1                 # ms; > 0, so that PortMidi keeps to the timestamps

"Runs `f` (a single PortMidi call) under PM_LOCK. Not for the audio thread, which uses `trylock`."
function pm_locked(f)
    lock(PM_LOCK)
    try
        return f()
    finally
        unlock(PM_LOCK)
    end
end

"(Re)initialises PortMidi; with `fresh` newly plugged devices are found. Call under MIDI_LOCK and PM_LOCK."
function pm_init!(fresh::Bool)
    PortMidi_jll.is_available() || return false
    if PM_READY[] && fresh && PM_OPEN[] == 0
        ccall((:Pm_Terminate, libpm), Cint, ())
        PM_READY[] = false
    end
    if !PM_READY[]
        ccall((:Pm_Initialize, libpm), Cint, ()) == 0 || return false
        PM_READY[] = true
    end
    return true
end

"""
    midi_devices(; fresh = true) -> Vector of (id, name, input, output)

All MIDI devices PortMidi knows. Empty if PortMidi or ALSA is not available.
"""
function midi_devices(; fresh::Bool = true)
    out = Tuple{Int,String,Bool,Bool}[]
    try
        lock(MIDI_LOCK) do                   # the device infos stay valid while it is held
            pm_locked(() -> pm_init!(fresh)) || return   # re-initialises only without open streams
            for id in 0:pm_locked(() -> ccall((:Pm_CountDevices, libpm), Cint, ()))-1
                p = pm_locked(() -> ccall((:Pm_GetDeviceInfo, libpm), Ptr{PmDeviceInfo}, (Cint,), id))
                p == C_NULL && continue
                d = unsafe_load(p)
                d.name == C_NULL && continue
                push!(out, (id, unsafe_string(d.name), d.input != 0, d.output != 0))
            end
        end
    catch e
        @debug "PortMidi not available" exception = e
    end
    return out
end

"""
    midi_inputs() -> Vector{String}

Names of the MIDI inputs. Re-initialises PortMidi (when no input is open) so newly plugged
devices appear. Empty, without an error, if PortMidi or ALSA is not available.
"""
midi_inputs() = unique!([d[2] for d in midi_devices() if d[3]])

"Names of the MIDI outputs, as [`midi_inputs`](@ref)."
midi_outputs() = unique!([d[2] for d in midi_devices() if d[4]])

"Starts the PortMidi clock (milliseconds) unless it runs. Call under PM_LOCK, before opening a stream."
pt_start!() = (ccall((:Pt_Started, libpm), Cint, ()) == 0 && ccall((:Pt_Start, libpm), Cint, (Cint, Ptr{Cvoid}, Ptr{Cvoid}), 1, C_NULL, C_NULL); nothing)

"Hit from the reader thread: receipt time (`time_ns()`), note number, velocity."
const MidiHit = @NamedTuple{t::UInt64, note::Int, vel::Int}

"An open MIDI input with its reader task."
mutable struct MidiInput
    name::String
    stream::Ptr{Cvoid}
    hits::Channel{MidiHit}
    running::Threads.Atomic{Bool}
    monitor::Threads.Atomic{Bool}        # also play the kit sound (through `pads`)
    cfg::MidiConfig
    pads::Channel{Tuple{Int,Int}}
    task::Union{Task,Nothing}
end

"Puts `x` into channel `ch` unless it is full (never blocks the reader)."
function try_put!(ch::Channel, x)
    lock(ch) do
        length(ch.data) < ch.sz_max && put!(ch, x)
    end
    return nothing
end

"""
Note-on of a PortMidi message: `(note, velocity)` for status 0x90–0x9F with velocity > 0,
`nothing` for everything else (velocity 0 is a note-off).
"""
function note_on(msg::Integer)
    st = msg & 0xff
    0x90 <= st <= 0x9f || return nothing
    vel = (msg >> 16) & 0x7f
    vel > 0 || return nothing
    return (Int((msg >> 8) & 0x7f), Int(vel))
end

"""
    open_midi(name; cfg = midi_config(), pads, monitor) -> MidiInput or nothing

Opens the MIDI input `name` and starts its reader on a background thread. `pads` is the
engine's pad channel for the monitor (kit sound per hit when `monitor[]`).
"""
function open_midi(name::AbstractString; cfg::MidiConfig = midi_config(),
                   pads::Channel{Tuple{Int,Int}} = Channel{Tuple{Int,Int}}(64),
                   monitor::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false))
    devs = midi_devices(; fresh = PM_OPEN[] == 0)
    k = findfirst(d -> d[3] && d[2] == name, devs)
    k === nothing && (logev("MIDI input not found"; name, inputs = [d[2] for d in devs if d[3]]); return nothing)
    ref = Ref{Ptr{Cvoid}}(C_NULL)
    err = lock(MIDI_LOCK) do
        pm_locked(pt_start!)
        e = pm_locked(() -> ccall((:Pm_OpenInput, libpm), Cint, (Ref{Ptr{Cvoid}}, Cint, Ptr{Cvoid}, Cint, Ptr{Cvoid}, Ptr{Cvoid}),
                                  ref, devs[k][1], C_NULL, 256, C_NULL, C_NULL))
        e == 0 && (PM_OPEN[] += 1; pm_locked(() -> ccall((:Pm_SetFilter, libpm), Cint, (Ptr{Cvoid}, Int32), ref[], PM_FILT)))
        e
    end
    err == 0 || (logev("MIDI input cannot be opened"; name, error = err); return nothing)
    m = MidiInput(String(name), ref[], Channel{MidiHit}(512), Threads.Atomic{Bool}(true), monitor, cfg, pads, nothing)
    m.task = Threads.@spawn midi_reader(m)
    logev("MIDI input opened"; name, ghost_accent = cfg.ghost => cfg.accent, offset_ms = cfg.offset_ms,
          levels = Dict(TRACK_IDS[t] => cfg.levels[t] for t in 1:NTRACKS if cfg.levels[t] != (cfg.ghost, cfg.accent)))
    return m
end

"Sleeps about 1 ms in a gc-safe call, so a garbage collection need not wait for this thread."
function sleep_1ms()
    @static if Sys.iswindows()
        @ccall gc_safe = true Sleep(1::UInt32)::Cvoid
    else
        @ccall gc_safe = true usleep(1000::Cuint)::Cint
    end
    return nothing
end

"Reader task: polls the input about every 1 ms and passes on note-ons (see [`note_on`](@ref))."
function midi_reader(m::MidiInput)
    buf = Vector{PmEvent}(undef, 64)
    try
        while m.running[]
            # explicit lock instead of a do-block: the closure would box `n` and allocate on every
            # pass (about 160 KB/s while idle)
            local n::Cint, now::UInt64, pt::Int32
            lock(PM_LOCK)
            try
                n = ccall((:Pm_Read, libpm), Cint, (Ptr{Cvoid}, Ptr{PmEvent}, Cint), m.stream, buf, length(buf))
            finally
                unlock(PM_LOCK)
            end
            now = time_ns()
            pt = ccall((:Pt_Time, libpm), Int32, ())            # the clock needs no lock
            for i in 1:max(n, 0)
                ev = buf[i]
                nv = note_on(ev.message)
                nv === nothing && continue
                age = clamp(pt - ev.timestamp, 0, 1000)           # ms between arrival and this read
                hit = (t = now - UInt64(age) * 1_000_000, note = nv[1], vel = nv[2])
                try_put!(m.hits, hit)
                if m.monitor[]
                    t = get(m.cfg.map, hit.note, 0)
                    t > 0 && try_put!(m.pads, (t, velocity_level(hit.vel, m.cfg, t)))
                end
            end
            # PortMidi stamps ALSA input only when it is read: poll on this thread without relying
            # on the event loop of the main thread (`sleep` could wake up much later)
            n > 0 || (sleep_1ms(); yield())
        end
    catch e
        @error "MIDI reader stopped" exception = (e, catch_backtrace())
    end
end

"Stops the reader, then closes the input."
function close_midi!(m::MidiInput)
    m.running[] = false
    m.task === nothing || try wait(m.task) catch end
    m.task = nothing
    lock(MIDI_LOCK) do
        m.stream == C_NULL && return
        pm_locked(() -> ccall((:Pm_Close, libpm), Cint, (Ptr{Cvoid},), m.stream))
        m.stream = C_NULL
        PM_OPEN[] = max(PM_OPEN[] - 1, 0)
        logev("MIDI input closed"; name = m.name)
    end
    return nothing
end
close_midi!(::Nothing) = nothing

"All hits received since the last call (for the GUI)."
function take_hits!(m::MidiInput)
    out = MidiHit[]
    while isready(m.hits)
        push!(out, take!(m.hits))
    end
    return out
end
# ---------------------------------------------------------------------------
# MIDI output: setup player (MIDI files) and main window (the sequencer plays a drum module)
# ---------------------------------------------------------------------------

# PortMidi opens a device only once: the player and the main window share the stream of a device
const OUT_STREAMS = Dict{String,Tuple{Ptr{Cvoid},Int}}()    # name -> (stream, users), under MIDI_LOCK

"""
    open_midi_out(name) -> Ptr (C_NULL if it cannot be opened)

Opens the MIDI output `name` with a latency of `MIDI_OUT_LATENCY` ms, so that PortMidi (ALSA)
sends each message at its timestamp. The same device may be open as input at the same time. If
the output is open already (player and main window), its stream is shared; each user closes it
with [`release_midi_out!`](@ref).
"""
function open_midi_out(name::AbstractString)
    shared = lock(MIDI_LOCK) do
        s = get(OUT_STREAMS, name, nothing)
        s === nothing && return C_NULL
        OUT_STREAMS[name] = (s[1], s[2] + 1)
        return s[1]
    end
    shared == C_NULL || return shared
    devs = midi_devices(; fresh = PM_OPEN[] == 0)
    k = findfirst(d -> d[4] && d[2] == name, devs)
    k === nothing && return C_NULL
    ref = Ref{Ptr{Cvoid}}(C_NULL)
    lock(MIDI_LOCK) do
        pm_locked(pt_start!)
        e = pm_locked(() -> ccall((:Pm_OpenOutput, libpm), Cint,
                                  (Ref{Ptr{Cvoid}}, Cint, Ptr{Cvoid}, Cint, Ptr{Cvoid}, Ptr{Cvoid}, Cint),
                                  ref, devs[k][1], C_NULL, 1024, C_NULL, C_NULL, MIDI_OUT_LATENCY))
        e == 0 ? (PM_OPEN[] += 1; OUT_STREAMS[String(name)] = (ref[], 1)) : (ref[] = C_NULL)
    end
    logev(ref[] == C_NULL ? "MIDI output cannot be opened" : "MIDI output opened"; name)
    return ref[]
end

"""
    release_midi_out!(p, chans)

Sends All Notes Off (controller 123) at once on the channels `chans` (bit c = channel c + 1) of
stream `p` and closes it when no other user has it open.
"""
function release_midi_out!(p::Ptr{Cvoid}, chans::UInt16)
    lock(MIDI_LOCK) do
        for ch in 0:15                               # timestamp 0: at once
            chans & (UInt16(1) << ch) == 0 && continue
            pm_locked(() -> ccall((:Pm_WriteShort, libpm), Cint, (Ptr{Cvoid}, Int32, Int32), p, 0, Int32(0xb0 | ch | 123 << 8)))
        end
        k = findfirst(s -> s[1] == p, OUT_STREAMS)
        if k !== nothing && OUT_STREAMS[k][2] > 1
            OUT_STREAMS[k] = (p, OUT_STREAMS[k][2] - 1)
            return
        end
        k === nothing || delete!(OUT_STREAMS, k)
        sleep(0.01)                                  # sent before the port goes away
        pm_locked(() -> ccall((:Pm_Close, libpm), Cint, (Ptr{Cvoid},), p))
        PM_OPEN[] = max(PM_OPEN[] - 1, 0)
        logev("MIDI output closed")
    end
    return nothing
end

"""
    midi_out_close!(pl, lk)

Closes the MIDI output of player `pl`: takes it away from the audio thread first, waits for the
block that may still use it (`lk` is the engine lock, held while a block is rendered) and for the
events already scheduled, then sends All Notes Off on all 16 channels and closes it.
"""
function midi_out_close!(pl::Player, lk)
    p = Ptr{Cvoid}(pl.mout[])
    p == C_NULL && return nothing
    pl.mout[] = 0                                    # the audio thread sends nothing from now on
    lock(() -> (pl.moff = 0x0000), lk)               # a block still using the output is finished
    sleep(pl.mlat / 1000 + BLOCK / SR + 0.01)        # notes already scheduled are played
    release_midi_out!(p, 0xffff)
    return nothing
end

"""
    SeqOut()

MIDI output of the main window: while it is open, the sequencer sends its hits as notes on
channel 10 (notes `MIDI_OUT_NOTES`, velocity from level, ornament, track volume and `gain`)
instead of playing the kit, so a drum module plays the pattern or song with its own sounds. While
playing it also sends MIDI clock (24 per beat) after a Start, so the click of the module follows
the tempo (TD-27: Sync Mode EXTERNAL); Stop when playback ends. The audio thread times each
message for the moment the sound card plays the same point (as the player does).
"""
mutable struct SeqOut
    mout::Threads.Atomic{UInt}       # open stream (PortMidi), 0 = off; set once fully open
    mlat::Float64                    # ms from rendering a block to hearing it (set by start_audio!)
    mclk::Float64                    # MIDI clock as in `Player` (see `midi_clock!`)
    mfr::Int
    merr::Threads.Atomic{Int}        # dropped or failed writes since the output was opened
    t0::Float64                      # PortMidi time (ms) at which the current block is heard
    pos0::Int                        # engine sample position at the start of the block
    last::Float64                    # timestamp of the last message: kept non-decreasing
    offat::Vector{Float64}           # per track: time (ms) of the pending note-off, < 0 = none
    gain::Float64                    # velocity factor (level of the module against your own playing)
    started::Bool                    # Start sent, clock running
    clk_next::Float64                # engine sample of the next clock tick
    clk_dt::Float64                  # samples between ticks in the current beat
    clk_left::Int                    # ticks left in the current beat
    sent::Union{Nothing,Vector{Tuple{Float64,Int32}}}   # tests, warm-up: messages kept, not sent
end

SeqOut() = SeqOut(Threads.Atomic{UInt}(0), 0.0, 0.0, -1, Threads.Atomic{Int}(0), 0.0, 0, 0.0,
                  fill(-1.0, NTRACKS), 1.0, false, 0.0, 0.0, 0, nothing)

"The sequencer plays through the MIDI output (or records its messages in a test)."
seq_on(o::SeqOut) = o.mout[] != 0 || o.sent !== nothing

const SEQ_CH = 9                          # channel 10
const SEQ_NOTE_MS = 30.0                  # note length; ends earlier if the same note comes again
const SEQ_TRIES = 2000                    # tries for PM_LOCK before a message is dropped

"""
    midi_clock!(pl, N) -> Float64

Called once per audio block by `mix_player!`: the PortMidi time (ms) at which the first frame of
this block is heard, 0 without an output. The time of a block is smoothed over about 64 blocks,
because the audio thread renders in bursts (the sound server takes several blocks at once); after
a gap or a dropout of more than 50 ms the clock starts again. The heard time adds `pl.mlat`.
"""
function midi_clock!(pl::Union{Player,SeqOut}, N::Int)
    pl.mout[] == 0 && (pl.mfr = -1; return 0.0)
    now = Float64(ccall((:Pt_Time, libpm), Int32, ()))
    x = now - pl.mfr * (1000 / SR)                   # frame 0 of the clock, by this block
    if pl.mfr < 0 || abs(x - pl.mclk) > 50
        pl.mfr = 0; pl.mclk = now
    else
        pl.mclk += (x - pl.mclk) / 64
    end
    t = pl.mclk + pl.mfr * (1000 / SR) + pl.mlat
    pl.mfr += N
    return t
end

"""
Sends MIDI message `msg` to be heard at PortMidi time `t` (ms), from the audio thread: no
allocation, never waits. `false` if PortMidi is busy in another thread (try again on a later
frame; the timestamp still holds). Without an output, or if the output was opened after
`midi_clock!` ran in this block (no time yet), the event is skipped; a failed write drops it and
counts in `pl.merr`.
"""
@inline function midi_send!(pl::Union{Player,SeqOut}, msg::Int32, t::Float64)
    p = pl.mout[]
    (p == 0 || pl.mfr < 0) && return true
    trylock(PM_LOCK) || return false
    ts = max(unsafe_trunc(Int32, round(t)) - Int32(MIDI_OUT_LATENCY), Int32(1))   # 0 would mean "at once"
    e = ccall((:Pm_WriteShort, libpm), Cint, (Ptr{Cvoid}, Int32, Int32), Ptr{Cvoid}(p), ts, msg)
    unlock(PM_LOCK)
    e == 0 || Threads.atomic_add!(pl.merr, 1)
    return true
end

"All Notes Off (controller 123) at time `t` on the channels in `pl.moff`, from the audio thread. Busy: kept for the next block."
function midi_notes_off!(pl::Player, t::Float64)
    for ch in 0:15
        pl.moff & (UInt16(1) << ch) == 0 && continue
        midi_send!(pl, Int32(0xb0 | ch | 123 << 8), t) || return
        pl.moff &= ~(UInt16(1) << ch)
    end
    return
end

"Sends `msg` of the sequencer at time `t` (ms, not before the previous message); PortMidi busy: tries again, then drops it."
function seq_write!(o::SeqOut, msg::Int32, t::Float64)
    t = max(t, o.last); o.last = t
    o.sent === nothing || (push!(o.sent, (t, msg)); return)
    for _ in 1:SEQ_TRIES
        midi_send!(o, msg, t) && return
    end
    Threads.atomic_add!(o.merr, 1)
    return
end

"""
Start of an audio block at engine position `pos` (`N` frames): sets the MIDI time of the block
and sends the note-offs that are due by then.
"""
function seq_block!(o::SeqOut, pos::Int, N::Int, playing::Bool)
    o.pos0 = pos
    o.t0 = o.sent === nothing ? midi_clock!(o, N) : pos * (1000 / SR)
    seq_on(o) || return
    if o.started && !playing                         # playback ended: Stop, no more clock
        seq_write!(o, Int32(0xfc), o.t0)
        o.started = false; o.clk_left = 0
    end
    for t in eachindex(o.offat)
        0 <= o.offat[t] <= o.t0 || continue
        seq_write!(o, Int32(0x80 | SEQ_CH | MIDI_OUT_NOTES[t] << 8), o.offat[t])
        o.offat[t] = -1.0
    end
    return
end

"""
Note of track `t` with velocity `vel` at engine position `pos` (in the block of `seq_block!`).
Before a hi-hat note, controller 4 sets the opening as Roland modules expect: 127 closed, 0 open.
"""
function seq_note!(o::SeqOut, pos::Int, t::Int, vel::Int)
    ts = o.t0 + (pos - o.pos0) * (1000 / SR)
    n = MIDI_OUT_NOTES[t]
    if o.offat[t] >= 0                               # the same note again: end the previous one
        seq_write!(o, Int32(0x80 | SEQ_CH | n << 8), ts)
        o.offat[t] = -1.0
    end
    cc = n == 46 ? 0 : (n == 42 || n == 44) ? 127 : -1
    cc >= 0 && seq_write!(o, Int32(0xb0 | SEQ_CH | 4 << 8 | cc << 16), ts)
    seq_write!(o, Int32(0x90 | SEQ_CH | n << 8 | clamp(vel, 1, 127) << 16), ts)
    o.offat[t] = ts + SEQ_NOTE_MS
    return
end

"""
Beat of `n` clock ticks starting at engine sample `at`, `d` samples long (from `do_step!`): the
first beat after the start of playback also sends Start, so the module's click starts on it.
"""
function seq_beat!(o::SeqOut, at::Float64, d::Float64, n::Int)
    if !o.started
        seq_write!(o, Int32(0xfa), o.t0 + (at - o.pos0) * (1000 / SR))
        o.started = true
    end
    o.clk_next = at; o.clk_dt = d / max(n, 1); o.clk_left = n
    return
end

"Sends the clock tick due at engine sample `pos`."
function seq_tick!(o::SeqOut, pos::Int)
    seq_write!(o, Int32(0xf8), o.t0 + (pos - o.pos0) * (1000 / SR))
    o.clk_next += o.clk_dt; o.clk_left -= 1
    return
end

"""
    seq_out_close!(o, lk)

Closes the MIDI output of the main window: takes it away from the audio thread, waits for the
block in progress (`lk` = engine lock) and the notes already scheduled, then sends All Notes Off
on channel 10 and closes the stream (if the player does not use it as well).
"""
function seq_out_close!(o::SeqOut, lk)
    p = Ptr{Cvoid}(o.mout[])
    p == C_NULL && return nothing
    lock(lk) do                                      # Stop for the module's click, at once
        o.started && seq_write!(o, Int32(0xfc), o.t0)
        o.started = false; o.clk_left = 0
        o.mout[] = 0
        fill!(o.offat, -1.0)
    end
    sleep(o.mlat / 1000 + BLOCK / SR + SEQ_NOTE_MS / 1000 + 0.01)
    release_midi_out!(p, UInt16(1) << SEQ_CH)
    return nothing
end

"""
    seq_out_open!(o, lk, name) -> Bool

Opens the MIDI output `name` for the sequencer after closing the open one (`""` = off).
"""
function seq_out_open!(o::SeqOut, lk, name::AbstractString)
    seq_out_close!(o, lk)
    isempty(name) && return false
    p = open_midi_out(name)
    p == C_NULL && return false
    lock(lk) do
        o.merr[] = 0; o.last = 0.0; o.mfr = -1; o.started = false; o.clk_left = 0
        fill!(o.offat, -1.0)
        o.mout[] = UInt(p)
    end
    logev("sequencer MIDI output"; name)
    return true
end
