# Log file for error reports: warnings and errors from all packages, plus events of DrumMachine
# (start, audio, kit, MIDI, recording, calibration, export, songs). Only the program writes it
# (`run`, `player`), not scripts that use the package. At LOG_MAX bytes the file becomes
# drummachine.log.1 (an older .1 is deleted), so at most about twice that is kept.

const Logging = Base.CoreLogging                    # the Logging stdlib builds on it; no extra dependency
using .Logging: AbstractLogger, global_logger

"Local time with milliseconds, e.g. 2026-11-20 15:37:01.123."
function log_time(t = time())
    return Libc.strftime("%Y-%m-%d %H:%M:%S", t) * "." * lpad(floor(Int, 1000 * (t % 1)), 3, '0')
end

const LOG_MAX = 1_000_000
"Lines of a backtrace kept in the log."
const LOG_BT_LINES = 40

"Folder of the log file (XDG state directory)."
log_dir() = joinpath(get(ENV, "XDG_STATE_HOME", joinpath(homedir(), ".local", "state")), "DrumMachine")
"The log file; the previous one is `log_path() * \".1\"`."
log_path() = joinpath(log_dir(), "drummachine.log")

"""
Logger of the program: writes warnings, errors and the events of [`logev`](@ref) to the log file
and passes everything else on to the console logger `next` (events only go to the file).
"""
mutable struct DMLogger <: AbstractLogger
    next::AbstractLogger
    path::String
    io::Union{IOStream,Nothing}
    size::Int
    max::Int
    lock::ReentrantLock
end

const LOGGER = Ref{Union{DMLogger,Nothing}}(nothing)

Logging.min_enabled_level(l::DMLogger) = min(Logging.Info, Logging.min_enabled_level(l.next))
Logging.shouldlog(::DMLogger, args...) = true
Logging.catch_exceptions(::DMLogger) = true

function Logging.handle_message(l::DMLogger, level, message, _module, group, id, file, line; kwargs...)
    event = group === :dmevent
    if event || level >= Logging.Warn
        try
            write_log(l, level, message, file, line, kwargs)
        catch
        end
    end
    event && return nothing
    nx = l.next
    if level >= Logging.min_enabled_level(nx) && Logging.shouldlog(nx, level, _module, group, id)
        Logging.handle_message(nx, level, message, _module, group, id, file, line; kwargs...)
    end
    return nothing
end

"Text of a log value: exceptions with a shortened backtrace, everything else on one line."
function log_value(k, v)
    if k === :exception
        e, bt = v isa Tuple && length(v) == 2 ? v : (v, nothing)
        s = sprint(io -> bt === nothing ? showerror(io, e) : showerror(io, e, bt); context = :limit => true)
        ls = split(s, '\n')
        length(ls) > LOG_BT_LINES && (ls = vcat(ls[1:LOG_BT_LINES], "   … ($(length(ls) - LOG_BT_LINES) more lines)"))
        return "\n    " * join(ls, "\n    ")
    end
    return replace(sprint(print, v; context = :limit => true), '\n' => ' ')
end

function write_log(l::DMLogger, level, message, file, line, kwargs)
    lvl = level >= Logging.Error ? "ERROR" : level >= Logging.Warn ? "WARN " : "INFO "
    io = IOBuffer()
    print(io, log_time(), "  ", lvl, "  ", replace(string(message), '\n' => ' '))
    for (k, v) in kwargs
        k === :exception && continue
        print(io, "  ", k, "=", log_value(k, v))
    end
    level >= Logging.Warn && file !== nothing && print(io, "  (", basename(string(file)), ":", line, ")")
    for (k, v) in kwargs
        k === :exception && print(io, log_value(k, v))
    end
    println(io)
    b = take!(io)
    lock(l.lock) do
        l.size + length(b) > l.max && rotate_log!(l)
        l.io === nothing && return
        write(l.io, b)
        flush(l.io)
        l.size += length(b)
    end
    return nothing
end

"Starts a new log file: the current one becomes `.1` (an older `.1` is deleted)."
function rotate_log!(l::DMLogger)
    l.io === nothing || close(l.io)
    try
        isfile(l.path) && mv(l.path, l.path * ".1"; force = true)
        l.io = open(l.path, "a"); l.size = 0
    catch
        l.io = nothing
    end
    return l
end

"""
    start_log!(; path = log_path(), max = LOG_MAX) -> DMLogger or nothing

Installs the program's logger (once): opens the log file and writes a start entry with version,
Julia, system and threads. `nothing` if the file cannot be opened (the program runs on without a log).
"""
function start_log!(; path::AbstractString = log_path(), max::Integer = LOG_MAX, what::AbstractString = "program")
    LOGGER[] === nothing || return LOGGER[]
    l = try
        mkpath(dirname(path))
        sz = isfile(path) ? filesize(path) : 0
        DMLogger(global_logger(), String(path), open(path, "a"), sz, max, ReentrantLock())
    catch e
        @warn "Log file cannot be opened, no log" path exception = e
        return nothing
    end
    l.size > max && rotate_log!(l)
    global_logger(l)
    LOGGER[] = l
    atexit(stop_log!)
    logev("start: " * what; version = app_version(), julia = VERSION, os = "$(Sys.KERNEL) $(Sys.MACHINE)",
          threads = Threads.nthreads(), lang = LANG[])
    return l
end

"Removes the program's logger again and closes the file."
function stop_log!()
    l = LOGGER[]
    l === nothing && return
    LOGGER[] = nothing
    global_logger() === l && global_logger(l.next)
    lock(l.lock) do
        l.io === nothing || close(l.io)
        l.io = nothing
    end
    return
end

"""
    logev(msg; kw...)

Event for the log file (only while the program's logger runs; not shown in the terminal, not
written by scripts). Keyword arguments are written as `key=value`.
"""
function logev(msg::AbstractString; kw...)
    LOGGER[] === nothing && return nothing
    @info msg _group = :dmevent kw...
    return nothing
end
