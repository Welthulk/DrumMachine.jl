# Setups (set lists) for the setup player: an ordered list of songs (.toml), audio files (.wav)
# and MIDI files (.mid), each with the pause before it and whether countdown beeps announce it.
#
# File: <data dir>/setlists/<name>.toml (private, outside the repository)
#     name = "Gig"
#     [[song]]
#     file = "/home/me/songs/Rock 8tel.toml"     # absolute, or relative to the song folder
#     pause = 5.0                                # seconds before the song (auto mode)
#     beep = true                                # countdown beeps in the last 3 s of the pause

mutable struct SetEntry
    path::String
    pause::Float64
    beep::Bool
end
SetEntry(path::AbstractString; pause::Real = 0.0, beep::Bool = false) = SetEntry(String(path), Float64(pause), beep)

mutable struct Setlist
    name::String
    entries::Vector{SetEntry}
end
Setlist(name::AbstractString = "Setup") = Setlist(String(name), SetEntry[])   # i18n-ok: default name

setlist_dir() = joinpath(data_dir(), "setlists")
setlist_path(name::AbstractString) = joinpath(setlist_dir(), safe_song_name(name) * ".toml")

"Names of the saved setups (file names without .toml), sorted."
function list_setlists()
    d = setlist_dir()
    isdir(d) || return String[]
    return sort([splitext(f)[1] for f in readdir(d) if endswith(f, ".toml")])
end

"Absolute path of an entry: relative paths are relative to the song folder."
entry_file(e::SetEntry) = isabspath(e.path) ? e.path : joinpath(song_dir(), e.path)

is_audio_file(path::AbstractString) = lowercase(splitext(path)[2]) == ".wav"
is_midi_file(path::AbstractString) = lowercase(splitext(path)[2]) in (".mid", ".midi")

"Loop export of the drum machine (`<name> Loop.wav`): made to repeat endlessly, not for the player."
is_loop_file(path::AbstractString) = occursin(r"(^|[\s_-])loop\.wav$"i, basename(path))

"Title shown on the button: song name from the .toml, file name for audio and MIDI files."
function entry_title(e::SetEntry)
    f = entry_file(e)
    if !is_audio_file(f) && !is_midi_file(f) && isfile(f)
        try
            n = get(TOML.parsefile(f), "name", "")
            n isa AbstractString && !isempty(n) && return String(n)
        catch
        end
    end
    return splitext(basename(f))[1]
end

function save_setlist(path::AbstractString, sl::Setlist)
    mkpath(dirname(path))
    d = Dict{String,Any}("name" => sl.name,
                         "song" => [Dict{String,Any}("file" => e.path, "pause" => e.pause, "beep" => e.beep)
                                    for e in sl.entries])
    tmp = path * ".tmp"
    open(io -> TOML.print(io, d; sorted = true), tmp, "w")
    mv(tmp, path; force = true)
    return path
end
save_setlist(sl::Setlist) = save_setlist(setlist_path(sl.name), sl)

function load_setlist(path::AbstractString)
    d = TOML.parsefile(path)
    sl = Setlist(String(get(d, "name", splitext(basename(path))[1])))
    for e in get(d, "song", [])
        f = get(e, "file", "")
        f isa AbstractString && !isempty(f) || continue
        p = get(e, "pause", 0.0); b = get(e, "beep", false)
        push!(sl.entries, SetEntry(f; pause = p isa Real ? clamp(p, 0, 600) : 0.0, beep = b === true))
    end
    return sl
end

"Kit for a song: the kit named in the song if installed, else the 808 synth kit."
function kit_for_song(s::Song)
    es = kit_entries()
    k = findfirst(e -> e.name == s.kit, es)
    k === nothing && (k = findfirst(e -> e.name == "808 (Synth)", es))
    return get_kit(es[something(k, 1)])
end

"""
    prepare_entry_cue(e) -> (audio, count-in frames, midi)

Audio of an entry, stereo at the engine sample rate: a song is rendered like the WAV export
(with its repeats, count-in and effects; never as a seamless loop), an audio file is read and
resampled if necessary. Loop WAVs (`… Loop.wav`) are refused. `midi` is `nothing`, except for a
MIDI file: its audio is silence of the file's length, `midi` = (frames, messages, channels) of
its events (frame 1 = start of the entry, see [`read_midi_file`](@ref)).
"""
function prepare_entry_cue(e::SetEntry)
    f = entry_file(e)
    isfile(f) || error(L("Datei nicht gefunden: {1}", f))
    is_loop_file(f) && error(L("Loop-WAV, im Player nicht verwendbar: {1}", basename(f)))
    if is_midi_file(f)
        m = read_midi_file(f)
        m.length <= 3600 || error(L("MIDI-Datei länger als 60 min: {1}", basename(f)))   # silence would take > 1 GB
        n = max(1, round(Int, m.length * SR))
        frames = [clamp(round(Int, t * SR) + 1, 1, n) for t in m.times]
        return zeros(Float32, n, 2), 0, (frames, m.msgs, midi_channels(m.msgs))
    end
    if is_audio_file(f)
        w = load_wave(f)
        y = size(w.data, 2) == 1 ? hcat(w.data, w.data) : w.data[:, 1:2]
        if w.fs != SR
            y = hcat(resample_sinc(y[:, 1], w.fs, SR), resample_sinc(y[:, 2], w.fs, SR))
        end
        return Matrix{Float32}(y), 0, nothing
    end
    s = load_song(f); s.loop = false                       # a loop song plays once, with its ending
    y = render_song(s, kit_for_song(s); loop = false)
    ci = round(Int, (song_seconds(s) - song_seconds(s; countin = 0)) * SR)   # count-in at the start
    return y, clamp(ci, 0, size(y, 1)), nothing
end

"Loads setup `sl` into the player: entries empty until `prepare_entry_cue` filled them."
function player_load!(pl::Player, sl::Setlist)
    player_stop!(pl)
    n = length(sl.entries)
    pl.items = [zeros(Float32, 0, 2) for _ in 1:n]
    pl.cues = zeros(Int, n)
    pl.mframe = [Int[] for _ in 1:n]; pl.mmsg = [Int32[] for _ in 1:n]; pl.mchans = zeros(UInt16, n)
    pl.delays = [e.pause for e in sl.entries]
    pl.beeps = [e.beep for e in sl.entries]
    pl.cur = 0
    return pl
end

"Player master settings as stored in the settings file (table `player`), with the MIDI output `midi_out`."
function player_settings(pl::Player, eqv::NTuple{4,Float64}, gain_db::Real, last::AbstractString,
                         midi_out::AbstractString = "")
    Dict{String,Any}("gain_db" => Float64(gain_db), "eq_low" => eqv[1], "eq_mid" => eqv[2],
                     "eq_midf" => eqv[3], "eq_high" => eqv[4], "hall" => PLAYER_HALLS[pl.hall],
                     "hall_mix" => Float64(pl.hallmix), "beep" => Float64(pl.beepgain), "route" => PLAYER_ROUTES[pl.route], "auto" => pl.auto,
                     "setlist" => String(last), "midi_out" => String(midi_out))
end
