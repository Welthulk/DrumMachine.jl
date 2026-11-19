# Setup player, audio part: plays prepared songs (rendered .toml songs, .wav files or .mid files)
# one after another, with a pause and optional countdown beeps before each song, through its own
# master section (volume, 3-band EQ, reverb). The engine mixes it into its output after everything
# else, so it shares the sound card with the main window; the audio thread does not allocate here.
# A MIDI file plays as silence of its length; its events go out from the audio thread to the MIDI
# output (see `midi_send!` in src/midi.jl), timed for the moment that block reaches the speaker.

const PLAYER_HALLS = ["Aus", "Raum", "Saal", "Kathedrale"]   # i18n-ok: shown via Ls()
# Output routing: stereo with beeps on both channels, or music in mono on one channel and the
# beeps alone on the other (that one goes to the band's headphones, not to the PA)
const PLAYER_ROUTES = ["Stereo, Beep auf beiden", "Musik links, Beep rechts", "Musik rechts, Beep links"]   # i18n-ok: shown via Ls()
const BEEP_SECONDS = 3            # countdown beeps in the last seconds of a pause, one per second
const PLAYER_TAIL = 4SR           # frames the reverb keeps ringing after the last song

"Short countdown beep (1 kHz, 0.12 s, soft attack and release)."
function beep_sound()
    n = round(Int, 0.12SR)
    env(k) = min(1, k / (0.005SR), (n - k) / (0.02SR))
    return Float32[0.35 * env(k) * sin(2π * 1000 * k / SR) for k in 0:n-1]
end

mutable struct Player
    items::Vector{Matrix{Float32}}    # audio per entry (frames × 2 at SR); empty = not ready
    cues::Vector{Int}                 # frames at the start of each entry that are the count-in (a cue)
    delays::Vector{Float64}           # pause before each entry in s
    beeps::Vector{Bool}               # countdown beeps before each entry
    auto::Bool                        # true: continue with the next entry after its pause
    state::Int                        # 0 idle, 1 pause before `cur`, 2 playing `cur`
    cur::Int
    pos::Int                          # next frame of the current entry
    wait::Int                         # frames left in the pause
    tail::Int                         # frames of reverb tail left after stopping at the end
    beep::Vector{Float32}
    beeppos::Int                      # position in the beep, 0 = silent
    beepgain::Float32                 # volume of the beeps (0 = off)
    route::Int                        # index into PLAYER_ROUTES
    gain::Float32                     # master volume (factor)
    eq::TrackFX                       # 3-band EQ (only the biquads are used)
    eqon::Bool
    hall::Int                         # index into PLAYER_HALLS (1 = off)
    hallmix::Float32
    halls::Vector{Reverb}             # room, hall, cathedral
    # display (read by the GUI)
    shown_state::Threads.Atomic{Int}
    shown_cur::Threads.Atomic{Int}
    shown_pos::Threads.Atomic{Int}    # frames played of the current entry
    shown_wait::Threads.Atomic{Int}   # frames left in the pause
    # MIDI entries: events per entry (frame from the entry start, PortMidi message), empty for audio
    mframe::Vector{Vector{Int}}
    mmsg::Vector{Vector{Int32}}
    mchans::Vector{UInt16}            # channels used per entry (bit c = channel c + 1)
    mi::Int                           # next event of the current entry
    moff::UInt16                      # channels still waiting for All Notes Off
    mout::Threads.Atomic{UInt}        # open MIDI output (PortMidi stream), 0 = none; set once fully open
    mlat::Float64                     # ms from rendering a block to hearing it (set by start_audio!)
    mclk::Float64                     # smoothed PortMidi time (ms) of frame 0 of the MIDI clock
    mfr::Int                          # frames since frame 0 of the MIDI clock, -1 = not started
    merr::Threads.Atomic{Int}         # failed MIDI writes since the output was opened (unplugged?)
end

Player() = Player(Matrix{Float32}[], Int[], Float64[], Bool[], true, 0, 0, 1, 0, 0, beep_sound(), 0, 1f0, 1,
                  1f0, TrackFX(), false, 1, 0.25f0,
                  [Reverb(0.80, 0.35), Reverb(0.92, 0.2), Reverb(0.97, 0.12)],
                  Threads.Atomic{Int}(0), Threads.Atomic{Int}(0), Threads.Atomic{Int}(0), Threads.Atomic{Int}(0),
                  Vector{Int}[], Vector{Int32}[], UInt16[], 1, 0x0000, Threads.Atomic{UInt}(0), 0.0, 0.0, -1,
                  Threads.Atomic{Int}(0))

player_active(pl::Player) = pl.state != 0 || pl.beeppos > 0 || pl.tail > 0 || pl.moff != 0

"The current entry stops: its MIDI channels get All Notes Off (sent by `mix_player!`)."
midi_end!(pl::Player) = (pl.state == 2 && 1 <= pl.cur <= length(pl.mchans) && (pl.moff |= pl.mchans[pl.cur]); pl)

"Sets the EQ of the player (dB low, dB mid, mid frequency in Hz, dB high)."
function player_eq!(pl::Player, low::Real, mid::Real, midf::Real, high::Real)
    update_eq!(pl.eq, Float32(low), Float32(mid), Float32(midf), Float32(high))
    pl.eqon = low != 0 || mid != 0 || high != 0
    return pl
end

"Starts entry `i`: with its pause (and beeps) if `pause`, otherwise immediately."
function player_start!(pl::Player, i::Int; pause::Bool)
    1 <= i <= length(pl.items) || return pl
    midi_end!(pl)
    pl.cur = i; pl.pos = 1; pl.tail = 0; pl.mi = 1
    w = pause ? round(Int, max(pl.delays[i], 0) * SR) : 0
    if w > 0
        pl.state = 1; pl.wait = w
    else
        pl.state = 2
    end
    pl.shown_cur[] = i; pl.shown_state[] = pl.state; pl.shown_pos[] = 0; pl.shown_wait[] = w
    return pl
end

"Stops the player at once (the reverb tail is cut as well)."
function player_stop!(pl::Player)
    midi_end!(pl)
    pl.state = 0; pl.tail = 0; pl.beeppos = 0
    foreach(clear!, pl.halls)
    pl.shown_state[] = 0
    return pl
end

"End of the current entry: next one in auto mode (skipping entries that are not ready), else idle."
function player_next!(pl::Player)
    midi_end!(pl)
    if pl.auto
        for j in pl.cur+1:length(pl.items)
            isempty(pl.items[j]) && continue
            return player_start!(pl, j; pause = true)
        end
    end
    pl.state = 0; pl.tail = PLAYER_TAIL
    pl.shown_state[] = 0
    return pl
end

@inline softclip(x::Float32) = abs(x) <= 0.8f0 ? x : copysign(0.8f0 + 0.2f0 * tanh((abs(x) - 0.8f0) / 0.2f0), x)

"""
Sends the MIDI events of the current entry that are due at its frame `pl.pos`; `k` is the frame
in the block, `t0` the time the block is heard (see [`midi_clock!`](@ref)).
"""
@inline function midi_events!(pl::Player, k::Int, t0::Float64)
    c = pl.cur
    c <= length(pl.mframe) || return
    fr = pl.mframe[c]
    @inbounds while pl.mi <= length(fr) && fr[pl.mi] <= pl.pos
        midi_send!(pl, pl.mmsg[c][pl.mi], t0 + (k - 1 - (pl.pos - fr[pl.mi])) * (1000 / SR)) || return
        pl.mi += 1
    end
    return
end

"Adds the player to the engine output `out` (frames × 2). Also sends the MIDI events of the block."
function mix_player!(pl::Player, out::Matrix{Float32})
    N = size(out, 1)
    t0 = midi_clock!(pl, N)
    pl.moff == 0 || midi_notes_off!(pl, t0)
    @inbounds for k in 1:N
        l = 0f0; r = 0f0; cue = 0f0
        if pl.state == 1                              # pause, with countdown beeps
            w = pl.wait
            if pl.beeps[pl.cur] && pl.beepgain > 0 && w <= BEEP_SECONDS * SR && w % SR == 0
                pl.beeppos = 1
            end
            pl.wait = w - 1
            pl.wait <= 0 && (pl.state = 2; pl.pos = 1)
        elseif pl.state == 2
            d = pl.items[pl.cur]
            if pl.pos <= size(d, 1)
                midi_events!(pl, k, t0)
                if pl.pos <= pl.cues[pl.cur]          # count-in of the song: a cue like the beeps
                    cue = (d[pl.pos, 1] + d[pl.pos, 2]) * 0.5f0
                else
                    l = d[pl.pos, 1]; r = d[pl.pos, 2]
                end
                pl.pos += 1
            else
                player_next!(pl)
                pl.moff == 0 || midi_notes_off!(pl, t0 + (k - 1) * (1000 / SR))
            end
        elseif pl.tail > 0
            pl.tail -= 1
        end
        if pl.eqon
            l, r = process(pl.eq.low, l, r)
            l, r = process(pl.eq.mid, l, r)
            l, r = process(pl.eq.high, l, r)
        end
        if pl.hall > 1
            wl, wr = process(pl.halls[pl.hall-1], l, r)
            l += pl.hallmix * wl; r += pl.hallmix * wr
        end
        l *= pl.gain; r *= pl.gain
        b = cue * pl.beepgain                        # cues (beeps, count-in) after EQ, reverb and
        if pl.beeppos > 0                            # master volume, with their own volume
            b += pl.beep[pl.beeppos] * pl.beepgain
            pl.beeppos = pl.beeppos < length(pl.beep) ? pl.beeppos + 1 : 0
        end
        if pl.route == 1
            l += b; r += b
        else                                         # music mono on one side, beeps alone on the other
            m = (l + r) * 0.7071f0
            l, r = pl.route == 2 ? (m, b) : (b, m)
        end
        out[k, 1] += softclip(l)
        out[k, 2] += softclip(r)
    end
    pl.shown_state[] = pl.state
    pl.shown_cur[] = pl.cur
    pl.shown_pos[] = pl.pos - 1
    pl.shown_wait[] = pl.wait
    return out
end
