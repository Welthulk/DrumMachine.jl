# MIDI file export: the song as a Standard MIDI File (format 0, channel 10), e.g. for a DAW or
# MuseScore. The engine runs the song without audio (`eng.hits`), so swing, pattern tempo,
# ornaments, mute/solo, count-in and click land exactly where the WAV export plays them.

const MIDI_PPQ = 960                       # ticks per quarter note (divisible by 2, 3, 4, 6, 8)
"Note per track for the export, in `TRACKS` order: the TD-27 notes, which are also General MIDI."
const MIDI_OUT_NOTES = (36, 38, 37, 42, 46, 44, 48, 45, 43, 51, 53, 49)
const MIDI_CLICK_NOTES = (33, 34)          # metronome click, bell (accent on beat 1)
"Velocity for ghost note, normal, accent (fit the recording thresholds 45 and 105)."
const MIDI_OUT_VEL = (35, 90, 120)
const MIDI_NOTE_LEN = MIDI_PPQ ÷ 8         # note length: a 32nd, shorter if the same note follows
"Controller 4 (hi-hat opening) before each hi-hat note: closed and pedal 127, open 0."
const MIDI_HH_CC4 = Dict(42 => 127, 44 => 127, 46 => 0)

"Kit without samples for the dry run of the engine."
dry_kit() = Kit("", [[Sample[]] for _ in 1:NTRACKS], zeros(Float32, NTRACKS), ones(Float32, NTRACKS),
                zeros(Int, NTRACKS))

"""
    song_hits(song; repeats, countin, click, loop = false) -> (hits, bars, total)

Runs the song through the engine without audio, with the same events as [`render_song`](@ref)
(see [`start_offline!`](@ref)). `hits` are `(sample, track, level, gain)` (track 0 = click),
`bars` are `(start sample, bpm, steps, steps_per_beat)` per bar, `total` is the end of the last
step in samples. Times count from the first sample of the WAV export: grace notes before step 1
go to the end with `loop = true` (as in the loop WAV); without loop and count-in they sit in a
pickup before step 1 (see [`export_pickup`](@ref)), so `bars[1][1]` is its length.
"""
function song_hits(song::Song; repeats::Int = song.repeats, countin::Int = song.countin,
                   click::Bool = song.click, loop::Bool = false)
    loop && (countin = 0)
    s = copy(song)
    s.click = click
    eng = Engine(s, dry_kit())
    eng.hits = Tuple{Int,Int,Int,Float32}[]
    bars = Tuple{Float64,Float64,Int,Int}[]
    start_offline!(eng; countin, repeats)
    L = round(Int, eng.next_step_at)
    a = loop ? L : offline_start(eng)          # time 0 of the result, as in render_song
    while true                                 # one sample resolution, like render!
        tnext, k = next_event(eng)
        isfinite(tnext) || break
        eng.samplepos = max(eng.samplepos, ceil(Int, tnext))
        if k == 0 && eng.step == 0
            p = current_pattern(eng)
            push!(bars, (eng.next_step_at - a, Float64(pattern_bpm(s, p)), p.steps, s.steps_per_beat))
        end
        fire_event!(eng, k)
    end
    total = eng.next_step_at - a
    hits = eng.hits
    for (i, h) in enumerate(hits)
        x = h[1] - a
        loop && x < 0 && (x += round(Int, total))   # grace notes of step 1: before the loop point
        hits[i] = (x, h[2], h[3], h[4])
    end
    return hits, bars, total
end

"""
Time signature (numerator, denominator) of a bar, `nothing` if it has none: a triplet bar that is
not a whole number of 8ths (e.g. 10 or 16 steps at 3 steps per beat) has no exact signature.
"""
function bar_signature(steps::Int, spb::Int)
    steps % spb == 0 && return (steps ÷ spb, 4)
    spb in (2, 4, 8) && return (steps, 4spb)
    spb == 6 && steps % 3 == 0 && return (steps ÷ 3, 8)    # whole 8ths, e.g. 9 steps = 3/8
    return nothing
end

"""
`false` if a bar of the chain has no exact time signature (see [`bar_signature`](@ref)): in the
MIDI file the bar lines are shifted from that bar on.
"""
midi_bars_ok(song::Song) = all(i -> bar_signature(song.patterns[i].steps, song.steps_per_beat) !== nothing, song.chain)

"Variable-length quantity of a MIDI file."
function vlq(n::Integer)
    out = UInt8[n & 0x7f]
    n >>= 7
    while n > 0
        pushfirst!(out, 0x80 | (n & 0x7f)); n >>= 7
    end
    return out
end

"""
    midi_events(song; repeats, countin, click, loop) -> (events, endtick)

Events of the MIDI track as `(tick, order, bytes)`, sorted; `order` puts meta events before
note-offs before note-ons at the same tick. Each hi-hat note comes right after a controller 4
(hi-hat opening, as on Roland modules) on the same tick: 127 (closed) for the closed and pedal
hi-hat, 0 (open) for the open hi-hat.
"""
function midi_events(song::Song; kw...)
    hits, bars, _ = song_hits(song; kw...)
    ev = Tuple{Int,Int,Vector{UInt8}}[]
    # bars: start tick, tempo and time signature changes
    btick = zeros(Int, length(bars))
    bpm0 = 0.0; sig0 = nothing; t = 0
    signature!(t, sig) = push!(ev, (t, 0, UInt8[0xff, 0x58, 0x04, sig[1], trailing_zeros(sig[2]), 24, 8]))
    if !isempty(bars) && bars[1][1] > 0
        # grace notes before step 1: a pickup bar of a 16th or longer, as long as in the WAV
        # (see `export_pickup`), so that the bars stay on the grid
        t = round(Int, bars[1][1] / (60 / bars[1][2] * SR) * MIDI_PPQ)
        sig0 = (1, 4MIDI_PPQ ÷ t); signature!(0, sig0)
    end
    for (b, (_, bpm, steps, spb)) in enumerate(bars)
        btick[b] = t
        if bpm != bpm0
            us = round(Int, 60e6 / bpm)
            push!(ev, (b == 1 ? 0 : t, 0, UInt8[0xff, 0x51, 0x03, (us >> 16) & 0xff, (us >> 8) & 0xff, us & 0xff]))
            bpm0 = bpm
        end
        sig = bar_signature(steps, spb)
        if sig !== nothing && sig != sig0
            signature!(t, sig); sig0 = sig
        end
        t += round(Int, steps * MIDI_PPQ / spb)
    end
    endtick = t
    starts = first.(bars)
    function tick(x)
        b = max(1, searchsortedlast(starts, x))
        return max(0, btick[b] + round(Int, (x - starts[b]) / (60 / bars[b][2] * SR) * MIDI_PPQ))
    end
    # notes; the same note twice on one tick (grace note squeezed onto its main note): louder stays
    notes = Dict{Tuple{Int,Int},Int}()
    for (x, tr, lv, g) in hits
        n = tr == 0 ? MIDI_CLICK_NOTES[lv == 3 ? 2 : 1] : MIDI_OUT_NOTES[tr]
        v = clamp(round(Int, MIDI_OUT_VEL[lv] * g), 1, 127)
        key = (n, min(tick(x), endtick))
        notes[key] = max(get(notes, key, 0), v)
    end
    ks = sort!(collect(keys(notes)))
    for (i, (n, tk)) in enumerate(ks)
        nxt = i < length(ks) && ks[i+1][1] == n ? ks[i+1][2] : typemax(Int)
        cc = get(MIDI_HH_CC4, n, -1)                 # hi-hat opening right before the note
        cc >= 0 && push!(ev, (tk, 2, UInt8[0xb9, 4, cc]))
        push!(ev, (tk, 2, UInt8[0x99, n, notes[(n, tk)]]))
        push!(ev, (max(tk + 1, min(tk + MIDI_NOTE_LEN, nxt, endtick)), 1, UInt8[0x89, n, 0]))
    end
    sort!(ev; by = e -> (e[1], e[2]), alg = Base.DEFAULT_STABLE)   # stable: CC 4 stays before its note
    return ev, max(endtick, isempty(ev) ? 0 : ev[end][1])
end

"""
    export_midi(path, song; repeats = song.repeats, countin, click = song.click, loop = song.loop) -> path

Writes the song as a Standard MIDI File (format 0, 960 ticks per quarter, channel 10): the
chain `repeats` times after `countin` count-in bars (none with `loop = true`). Notes per track
as on the Roland TD-27 and in General MIDI (kick 36, snare 38, side stick 37, hi-hat 42/46/44,
toms 48/43, ride 51, bell 53, crash 49), click 33 and 34. Ghost note, normal and accent get
velocity 35, 90 and 120. Before each hi-hat note, controller 4 (hi-hat opening, used by Roland
modules) is set on the same tick: 127 for closed (42) and pedal (44), 0 for open (46). Swing, pattern tempo (tempo changes), ornaments and mute/solo are
included. The file ends after the last bar.

A triplet bar that is not a whole number of 8ths (e.g. 10 or 16 steps at 3 steps per beat) has
no exact time signature: the previous one stays in effect, so from that bar on the bar lines in a
DAW or notation program are shifted. Pad such patterns to whole beats.
With `loop = true`, grace notes of a flam or drag on step 1 are at the end of the file, as in the
loop WAV; without loop and count-in they sit in a pickup bar before bar 1: a 16th (1/16), longer
for a long flam or drag at a fast tempo. The WAV export starts with the same pickup, so both
files line up at time 0.
"""
function export_midi(path::AbstractString, song::Song; repeats::Int = song.repeats,
                     loop::Bool = song.loop, countin::Int = loop ? 0 : song.countin, click::Bool = song.click)
    ev, endtick = midi_events(song; repeats, countin = loop ? 0 : countin, click, loop)
    trk = UInt8[]
    name = Vector{UInt8}(codeunits(song.name))
    append!(trk, 0x00, 0xff, 0x03, vlq(length(name)), name)
    last = 0
    for (t, _, bytes) in ev
        append!(trk, vlq(t - last), bytes); last = t
    end
    append!(trk, vlq(endtick - last), UInt8[0xff, 0x2f, 0x00])
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        write(io, b"MThd", hton(UInt32(6)), hton(UInt16(0)), hton(UInt16(1)), hton(UInt16(MIDI_PPQ)))
        write(io, b"MTrk", hton(UInt32(length(trk))), trk)
    end
    logev("MIDI file exported"; path, song = song.name, repeats, loop)
    return String(path)
end

# ---------------------------------------------------------------------------
# Reading MIDI files (setup player)
# ---------------------------------------------------------------------------

"""
Events of a MIDI file: channel messages packed as for PortMidi (`status | data1 << 8 |
data2 << 16`) with their time in s, in playing order, and the length in s (end of the longest track).
"""
struct MidiFileData
    times::Vector{Float64}
    msgs::Vector{Int32}
    length::Float64
end

"""
    read_midi_file(path) -> MidiFileData

Reads a Standard MIDI File of format 0 or 1 (the tracks are merged). Channel messages are kept,
also with running status; tempo changes (meta event 0x51) set the times in s, all other meta
events and sysex are skipped. A broken or unsupported file raises an error that says why.
"""
read_midi_file(path::AbstractString) = parse_midi(read(path), basename(path))

function parse_midi(b::AbstractVector{UInt8}, name::AbstractString = "MIDI")
    bad(why) = error(L("„{1}“ ist keine gültige MIDI-Datei: {2}", name, why))
    cut() = bad(L("Datei abgeschnitten"))
    function uint(i, k)                               # big-endian integer of k bytes at i
        i + k - 1 <= length(b) || cut()
        x = 0
        for j in i:i+k-1
            x = x << 8 | b[j]
        end
        return x
    end
    function varlen(i, stop)                          # variable-length quantity -> (value, next index)
        v = 0
        for _ in 1:4
            i <= stop || cut()
            c = b[i]; i += 1
            v = v << 7 | (c & 0x7f)
            c < 0x80 && return v, i
        end
        bad(L("Längenangabe zu lang"))
    end
    length(b) >= 14 && b[1:4] == b"MThd" || bad(L("kein MIDI-Kopf (MThd)"))
    fmt, ntrk, div = uint(9, 2), uint(11, 2), uint(13, 2)
    fmt in (0, 1) || bad(L("Format {1} wird nicht unterstützt, nur 0 und 1", fmt))
    div & 0x7fff == 0 && bad(L("Zeitbasis 0"))
    div & 0x8000 == 0 || (256 - div >> 8) in (24, 25, 29, 30) && div & 0xff > 0 || bad(L("ungültige SMPTE-Zeitbasis"))
    ev = Tuple{Int,Int,Int32}[]                      # (tick, file order, message)
    tempos = Tuple{Int,Int,Int}[]                    # (tick, file order, µs per quarter)
    endtick = 0; seq = 0; ntr = 0
    i = 9 + uint(5, 4)                               # first chunk after the header
    while ntr < ntrk && i + 7 <= length(b)
        id = b[i:i+3]; len = uint(i + 4, 4); i += 8
        stop = i + len - 1
        stop <= length(b) || cut()
        if id != b"MTrk"                             # unknown chunk: skipped, as the standard says
            i = stop + 1
            continue
        end
        ntr += 1
        t = 0; run = 0x00                            # running status
        while i <= stop
            d, i = varlen(i, stop)
            t += d
            i <= stop || cut()
            st = b[i]
            if st >= 0x80
                i += 1
            else
                run >= 0x80 || bad(L("Datenbyte ohne Status"))
                st = run
            end
            if st == 0xff || st == 0xf0 || st == 0xf7      # meta event or sysex: skipped, tempo kept
                typ = 0x00
                if st == 0xff
                    i <= stop || cut()
                    typ = b[i]; i += 1
                end
                n, i = varlen(i, stop)
                i + n - 1 <= stop || cut()
                typ == 0x51 && n == 3 && (u = uint(i, 3)) > 0 && push!(tempos, (t, seq += 1, u))
                i += n
                typ == 0x2f && st == 0xff && break             # end of track
            elseif st >= 0xf0
                bad(L("unbekanntes Ereignis 0x{1}", string(st, base = 16)))
            else
                run = st
                nd = 0xc0 <= st <= 0xdf ? 1 : 2              # program change, channel pressure: 1 byte
                i + nd - 1 <= stop || cut()
                d1 = b[i]; d2 = nd == 2 ? b[i+1] : 0x00
                (d1 | d2) < 0x80 || bad(L("Datenbyte ohne Status"))
                i += nd
                push!(ev, (t, seq += 1, Int32(st) | Int32(d1) << 8 | Int32(d2) << 16))
            end
        end
        endtick = max(endtick, t)
        i = stop + 1
    end
    ntr == 0 && bad(L("keine Spur (MTrk)"))
    ntr < ntrk && cut()                              # the header announces more tracks
    sort!(ev); sort!(tempos)                         # by tick, then file order (track 1 first)
    if div & 0x8000 != 0                             # SMPTE: frames per second × ticks per frame
        fps = 256 - div >> 8
        spt = 1 / ((fps == 29 ? 29.97 : fps) * (div & 0xff))
        sec = tk -> tk * spt
    else                                             # ticks per quarter note, tempo map
        tt = [0]; ts = [0.0]; us = [500_000]         # tempo change: tick, time in s, µs per quarter
        for (tk, _, u) in tempos
            if tk == tt[end]
                us[end] = u
            else
                push!(ts, ts[end] + (tk - tt[end]) * us[end] / (1e6 * div)); push!(tt, tk); push!(us, u)
            end
        end
        sec = tk -> (k = searchsortedlast(tt, tk); ts[k] + (tk - tt[k]) * us[k] / (1e6 * div))
    end
    return MidiFileData([sec(e[1]) for e in ev], [e[3] for e in ev], sec(endtick))
end

"Channels a list of PortMidi messages uses, as bits (bit c = channel c + 1)."
midi_channels(msgs::AbstractVector{Int32}) = reduce(|, (UInt16(1) << (m & 0x0f) for m in msgs); init = 0x0000)
