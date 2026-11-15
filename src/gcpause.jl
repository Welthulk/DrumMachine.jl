# Optional pause of Julia's garbage collector during playback.
#
# A collection briefly halts all threads, the audio thread included; if it takes longer than the
# audio buffer, playback crackles. With a GC pause set, the collector is switched off while the song
# or the metronome plays and comes back on stop, when the time is up, or when free memory runs low.
#
# `GC.enable` keeps its state per thread: switching it back on from another thread would leave the
# collector off for good. So `gcpause_update!` must always be called from the same task (the GUI loop).

const GC_PAUSE_OPTS = [0, 2, 5, 10, 20]                       # minutes, 0 = off
const GC_MIN_FREE = 1024^3                                    # re-enable below 1 GiB free memory

mutable struct GCPause
    minutes::Int          # chosen duration, 0 = off
    off::Bool             # collector currently switched off by us
    until::Float64        # time() at which it comes back on
    spent::Bool           # pause used up in this playback: don't start a new one before stop
    thread::Int           # thread that switched it off
end

const GCPAUSE = GCPause(0, false, 0.0, false, 0)

"Stored duration in minutes (`gc_pause` in the settings file), 0 if unset or invalid."
function gcpause_setting()
    v = get(load_settings(), "gc_pause", 0)
    return v isa Integer && v in GC_PAUSE_OPTS ? Int(v) : 0
end

"Switches the collector back on (if we switched it off). Returns `true` if it was off."
function gcpause_release!(g::GCPause = GCPAUSE)
    g.off || return false
    g.thread == Threads.threadid() || return false             # wrong thread: GC.enable would be a no-op
    GC.enable(true)
    g.off = false
    return true
end

"""
    gcpause_update!(active; g = GCPAUSE) -> Symbol

Call regularly with `active` = song or metronome playing. Returns what happened:
`:paused`, `:stopped` (playback ended), `:time` (time up), `:memory` (free memory low) or `:none`.
"""
function gcpause_update!(active::Bool; g::GCPause = GCPAUSE, free = Sys.free_memory())
    if g.off
        reason = !active ? :stopped : time() >= g.until ? :time : free < GC_MIN_FREE ? :memory : :none
        reason === :none && return :none
        gcpause_release!(g) || return :none
        g.spent = active
        return reason
    end
    active || (g.spent = false; return :none)
    (g.minutes == 0 || g.spent || free < GC_MIN_FREE) && return :none
    GC.gc(false)                                               # start with a clean young generation
    GC.enable(false)
    g.off = true; g.thread = Threads.threadid(); g.until = time() + 60 * g.minutes
    return :paused
end

"Sets the duration; 0 switches the collector back on right away."
function gcpause_set!(minutes::Integer; g::GCPause = GCPAUSE)
    g.minutes = Int(minutes)
    minutes == 0 && gcpause_release!(g)
    g.until = g.off ? min(g.until, time() + 60 * minutes) : g.until
    return g
end
