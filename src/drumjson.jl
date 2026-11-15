# Import of drum compositions in JSON ("Drum-JSON"), as saved by browser step sequencers.
#
# Layout: per track a `sound` (e.g. "acme_hihat", the part before "_" names the kit) and per slot
# (0-based across all bars) the velocity in `slot_volume` (0.01 … 1) and a sound variant in
# `slot_variant` (0 = main sound; 1 = open hi-hat / rim / ride bell; 2 = hi-hat pedal). Song
# settings: tempo, shuffle (0.5 = straight, 0.67 = triplet, as `song.swing`), beat_div (slots per
# beat), beats_per_bar, bars, kit, effect_type, effect_amount.

import JSON

"Sound name (without kit prefix) and variant -> track id here, or `nothing`."
function djson_track(sound::AbstractString, variant::Integer)
    s = lowercase(sound)
    s = occursin('_', s) ? s[findfirst('_', s)+1:end] : s          # drop the kit prefix
    v = variant
    contains(s, "kick") && return "Kick"
    if contains(s, "hihat") || contains(s, "hi_hat") || contains(s, "hat")
        contains(s, "open") && return "HHOpen"
        (contains(s, "close") || contains(s, "ped")) && return "HHPedal"
        return v == 1 ? "HHOpen" : v == 2 ? "HHPedal" : "HiHat"
    end
    (contains(s, "rim") || contains(s, "stick") || contains(s, "clap")) && return "Rim"
    contains(s, "snare") && return v == 1 ? "Rim" : "Snare"
    contains(s, "ride") && return (contains(s, "bell") || v == 1) ? "RideBell" : "Ride"
    contains(s, "bell") && return "RideBell"
    (contains(s, "crash") || contains(s, "china") || contains(s, "splash") || contains(s, "cymbal")) &&
        return "Crash"
    if contains(s, "tom")
        (contains(s, "lo") || contains(s, "floor")) && return "FloorTom"
        return "Tom"
    end
    return nothing
end

"Velocity (0 … 1) relative to the loudest hit of the track -> level 1 ghost, 2 normal, 3 accent."
function djson_level(v::Real, vmax::Real, varied::Bool)
    varied || return 0x02                    # all hits equally loud: normal
    r = v / vmax
    return r >= 0.85 ? 0x03 : r >= 0.45 ? 0x02 : 0x01
end

"Kit here for the kit name in the file."
function djson_kit(kit::AbstractString)
    k = lowercase(kit)
    contains(k, "808") && return "808 (Synth)"
    contains(k, "909") && return "909 (Synth)"
    contains(k, "blackpearl") && return "BlackPearl"
    return "CrocellKit"
end

"Master effect here for the effect type in the file."
function djson_fx(t)
    t isa AbstractString || return "Clean"
    k = lowercase(t)
    any(w -> contains(k, w), ("hall", "church", "cathedral", "plate", "arena")) && return "Hall"
    any(w -> contains(k, w), ("echo", "delay")) && return "Echo"
    any(w -> contains(k, w), ("studio", "room", "chamber")) && return "Room"
    return "Clean"
end

getnum(d, k, def) = (v = get(d, k, def); v isa Real ? Float64(v) : Float64(def))

"""
    import_drum_json(src; name = "") -> (song, notes)

Converts a Drum-JSON composition (`src`: file path or JSON text) into a `Song`. One
pattern per bar, identical bars share a pattern. `notes` lists what could not be taken over
(unknown sounds, merged toms, flams …).
"""
function import_drum_json(src::AbstractString; name::AbstractString = "")
    isjson = startswith(lstrip(src), "{")
    d = JSON.parse(isjson ? src : read(src, String))
    d isa AbstractDict && get(d, "tracks", nothing) isa AbstractVector ||
        error(L("Keine Drum-JSON-Datei (Feld „tracks“ fehlt)"))
    notes = String[]
    tracks = [t for t in d["tracks"] if t isa AbstractDict]
    slot_keys(t, k) = (x = get(t, k, nothing); x isa AbstractDict ? x : Dict{String,Any}())
    maxslot = maximum((parse(Int, k) for t in tracks for k in keys(slot_keys(t, "slot_volume"))); init = -1)

    div = round(Int, getnum(d, "beat_div", 4))
    bpb = round(Int, getnum(d, "beats_per_bar", 0))
    if bpb <= 0                                     # old files: guess 4, 3 or 5 beats
        nb = cld(maxslot + 1, div)
        bpb = something(findfirst(b -> nb % b == 0, (4, 3, 5)), 1) |> i -> (4, 3, 5)[i]
    end
    bars = max(1, round(Int, getnum(d, "bars", cld(maxslot + 1, div * bpb))))
    nslots = div * bpb * bars
    bpm = getnum(d, "tempo", 100)
    # slots per beat -> grid here: 2, 3, 4, 6 directly; 1 spread to 2; 8 = 16ths at double tempo
    spb, factor = div in (2, 3, 4, 6) ? (div, 1) : div == 1 ? (2, 2) : div == 8 ? (4, 1) : (0, 0)
    spb == 0 && error(L("Raster mit {1} Schlägen pro Viertel wird nicht unterstützt", div))
    if div == 8
        bpm *= 2; bpb *= 2
        push!(notes, L("32tel-Raster: als 16tel bei doppeltem Tempo übernommen"))
    end
    bpm = clamp(bpm, 30, 400)
    steps_bar = bpb * spb

    # hits per track here: level at each step (across all bars)
    grid = zeros(UInt8, NTRACKS, steps_bar * bars)
    params = Dict{String,Any}()                     # first source track per track here
    merged = Dict{String,Vector{String}}()
    for t in tracks
        snd = get(t, "sound", nothing)
        snd isa AbstractString || continue
        vols = slot_keys(t, "slot_volume")
        isempty(vols) && continue
        vars = slot_keys(t, "slot_variant")
        rep = round(Int, getnum(t, "repeat", 0))
        vs = [Float64(v) for v in values(vols) if v isa Real]
        vmax = maximum(vs; init = 1.0); varied = length(unique(vs)) > 1
        hits = Dict{Int,Float64}(parse(Int, k) => Float64(v) for (k, v) in vols if v isa Real && v > 0)
        if rep > 0                                  # track repeats after `rep` slots
            for s in rep:nslots-1
                v = get(hits, s % rep, 0.0)
                v > 0 ? (hits[s] = v) : delete!(hits, s)
            end
        end
        for (s, v) in hits
            0 <= s < nslots || continue
            var = get(vars, string(s), 0); var = var isa Real ? round(Int, var) : 0
            id = djson_track(snd, var)
            if id === nothing
                push!(notes, L("Unbekannter Klang „{1}“ übersprungen", snd)); continue
            end
            k = track_index(id)
            st = s * factor
            grid[k, st+1] = max(grid[k, st+1], djson_level(v, vmax, varied))
            haskey(params, id) || (params[id] = t)
            snd in get!(merged, id, String[]) || push!(merged[id], snd)
        end
        any(!isempty, (slot_keys(t, "slot_flam"), slot_keys(t, "slot_delay"))) &&
            push!(notes, L("Flams/Delays von „{1}“ nicht übernommen", snd))
        round(Int, getnum(t, "shift", 0)) != 0 && push!(notes, L("Verschiebung von „{1}“ nicht übernommen", snd))
    end
    for (id, snds) in merged
        length(snds) > 1 && push!(notes, L("{1} zusammengelegt auf {2}", join(snds, ", "), L(TRACKS[track_index(id)][2])))
    end

    # one pattern per bar, identical bars share a pattern
    pats = Pattern[]; chain = Int[]
    for b in 1:bars
        g = grid[:, (b-1)*steps_bar+1:b*steps_bar]
        k = findfirst(p -> p.grid[:, 1:steps_bar] == g, pats)
        if k === nothing
            p = Pattern(steps_bar); p.grid[:, 1:steps_bar] .= g
            push!(pats, p); k = length(pats)
        end
        push!(chain, k)
    end
    length(pats) > 16 && push!(notes, L("{1} verschiedene Takte – im Programm sind nur 16 Patterns bearbeitbar", length(pats)))

    sh = get(d, "shuffle", 0.5)
    sh = sh isa Bool ? (sh ? 2 / 3 : 0.5) : sh isa Real ? Float64(sh) : 0.5
    sh in (0, 1, 2, 3) && sh isa Integer && (sh = (0.5, 0.67, 0.6, 0.75)[Int(sh)+1])
    swing = spb in (3, 6) ? 2 / 3 : clamp(sh, 0.5, 0.8)
    nm = strip(String(get(d, "name", "")))
    generic = isempty(nm) || lowercase(nm) == "drums"           # default name: use the file name
    nm = !isempty(name) ? name : !generic ? nm : isjson ? "JSON-Import" : splitext(basename(src))[1]
    song = Song(name = nm, bpm = bpm, swing = swing, swing_on = spb == 4 ? 16 : 0, steps_per_beat = spb,
                patterns = pats, chain = chain, kit = djson_kit(String(get(d, "kit", ""))),
                fx = djson_fx(get(d, "effect_type", nothing)),
                fxmix = clamp(0.25 * getnum(d, "effect_amount", 1), 0, 1), repeats = 4)
    for (id, t) in params
        tp = song.tracks[track_index(id)]
        tp.vol = clamp(getnum(t, "volume", 1), 0, 1.5)
        tp.pan = clamp(getnum(t, "pan", 0), -1, 1)
        tp.pitch = clamp(getnum(t, "pitch", 0) + getnum(d, "pitch", 0), -12, 12)
    end
    return song, unique(notes)
end

"Is `text` a Drum-JSON composition?"
is_drum_json(text::AbstractString) =
    startswith(lstrip(text), "{") && occursin("\"tracks\"", text) && occursin("slot_volume", text)

"""
    import_drum_json_files(paths; dir = song_dir()) -> Vector{(path, song, notes)}

Imports several Drum-JSON files and saves each as `<name>.toml` in `dir` (an existing file is not
overwritten, the name gets a number).
"""
function import_drum_json_files(paths; dir::AbstractString = song_dir())
    res = []
    for p in paths
        song, notes = import_drum_json(p)
        push!(res, (save_song(free_song_path(dir, song), song), song, notes))
    end
    return res
end

"Path for `song` in `dir` that does not exist yet (`name`, `name 2`, …); renames the song."
function free_song_path(dir::AbstractString, song::Song)
    base = song.name; k = 2
    while isfile(joinpath(dir, safe_song_name(song.name) * ".toml"))
        song.name = "$base $k"; k += 1
    end
    return joinpath(dir, safe_song_name(song.name) * ".toml")
end
