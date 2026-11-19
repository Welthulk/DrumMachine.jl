# Building the large sample kits (CrocellKit, VirtuosityDrums) from their public downloads.
# Runs inside the package so it also works for an installed (read-only) package: archives go to
# the cache directory, built kits to the user's data directory. The scripts in tools/ call this.
#
# Steps per kit: download (with progress), extract (bsdtar from LibArchive_jll), pick velocity layers by
# measured level, resample to 44.1 kHz, trim, write 16-bit WAVs, calibrate the balance.

import Downloads
using FLAC_jll: flac
using LibArchive_jll: bsdtar

"User data directory (XDG): built kits live in its `kits` folder."
data_dir() = joinpath(get(ENV, "XDG_DATA_HOME", joinpath(homedir(), ".local", "share")), "DrumMachine")
user_kit_dir() = get(ENV, "DRUMMACHINE_KIT_DIR", joinpath(data_dir(), "kits"))
"Cache for downloaded archives (can be deleted after the build)."
cache_dir() = joinpath(get(ENV, "XDG_CACHE_HOME", joinpath(homedir(), ".cache")), "DrumMachine")

# Velocity layers: limits in dB relative to the instrument's loudest hit.
# Ghost notes = layers 1-2, normal = 3-4, accent = 5 (see `level_layers`).
const BIN_EDGES = [-32.0, -24.0, -17.0, -11.0, -5.0, 0.01]
const MAX_RR = 4

# Maximum length per track in seconds (the decay is faded out after that)
const MAXLEN = Dict("Kick" => 1.2, "Snare" => 1.2, "Rim" => 0.6, "HiHat" => 0.6, "HHOpen" => 2.5,
                    "HHPedal" => 0.6, "Tom" => 2.5, "FloorTom" => 3.0, "Ride" => 5.0,
                    "RideBell" => 4.0, "Crash" => 5.0)

# Balance: level of a "normal" hit (layers 3-4) relative to the snare in dB.
const BALANCE_DB = Dict("Kick" => 0.0, "Snare" => 0.0, "Rim" => -6.0, "HiHat" => -8.0,
                        "HHOpen" => -6.0, "HHPedal" => -12.0, "Tom" => -2.0, "FloorTom" => -2.0,
                        "Ride" => -6.0, "RideBell" => -6.0, "Crash" => -4.0)
const SNARE_NORMAL_PEAK = 0.3      # target level of a normal snare hit

"Attack level: peak value of the first 30 ms (all channels)."
attack_peak(y, fs) = maximum(abs, view(y, 1:min(size(y, 1), round(Int, 0.03fs)), :))

"Stereo matrix -> 44.1 kHz, trim to `maxlen`, soft fade-out over the last 30 %."
function prepare_sample(y::AbstractMatrix, fs, maxlen)
    l = resample_sinc(view(y, :, 1), fs, SR)
    r = resample_sinc(view(y, :, size(y, 2) > 1 ? 2 : 1), fs, SR)
    n = min(length(l), round(Int, maxlen * SR))
    l = l[1:n]; r = r[1:n]
    nf = round(Int, 0.3n)
    for k in 1:nf
        g = Float32(0.5 + 0.5cospi(k / nf))
        l[n-nf+k] *= g; r[n-nf+k] *= g
    end
    return hcat(l, r)
end

"""
    build_kit(dest, name, sources; header, license, choke, log = println)

`sources`: vector `track_id => loaders`, each loader is a function `() -> (y::Matrix, fs)`
`post`: optional processing of each prepared recording (stereo matrix at 44.1 kHz, peak ≤ 0.95).
(one recording, stereo or mono). Writes `dest/<track>/<layer>-<rr>.wav`, `kit.toml`, `LICENSE.txt`.
The kit is built in a temporary folder next to `dest` and moved into place at the end, so an
interrupted build never leaves a half-finished kit behind.
"""
function build_kit(dest, name, sources; header::AbstractString, license::AbstractString,
                   choke = ("HiHat", "HHOpen", "HHPedal"), post = nothing, log = println)
    tmp = build_tmp(dest)
    try
        build_kit_files(tmp, name, sources; header, license, choke, post, log)
    catch
        rm(tmp; recursive = true, force = true)       # no half-built folder left behind
        rethrow()
    end
    finish_build(tmp, dest, name; log)
end

function build_kit_files(tmp, name, sources; header, license, choke, post, log)
    refs = Dict{String,Float64}()
    for (k, (id, loaders)) in enumerate(sources)
        log(L("{1}: Instrument {2}/{3} ({4})", name, k, length(sources), id))
        stats = map(loaders) do ld
            y, fs = ld()
            (attack_peak(y, fs), maximum(abs, y))
        end
        peaks = first.(stats)
        db = 20 .* log10.(peaks ./ maximum(peaks))
        # loudest recording to -0.5 dBFS: no clipping of multi-mic mixes, quiet recordings use the
        # full 16-bit range; the gain in kit.toml compensates
        scale = 0.95 / maximum(last.(stats))
        mkpath(joinpath(tmp, id))
        for b in 1:length(BIN_EDGES)-1
            lo, hi = BIN_EDGES[b], BIN_EDGES[b+1]
            idx = [i for i in eachindex(db) if lo <= db[i] < hi]
            isempty(idx) && (idx = sortperm(abs.(db .- (lo + hi) / 2))[1:1])   # empty layer: nearest recording
            idx = sort(idx; by = i -> db[i])
            pick = length(idx) <= MAX_RR ? idx : idx[round.(Int, range(1, length(idx), length = MAX_RR))]
            for (rr, i) in enumerate(unique(pick))
                y, fs = loaders[i]()
                out = prepare_sample(y, fs, MAXLEN[id]) .* Float32(scale)
                post === nothing || (out = post(out))
                pcm = round.(Int16, clamp.(out, -1, 1) .* 32767)
                WAV.wavwrite(pcm, joinpath(tmp, id, "$b-$rr.wav"); Fs = SR, nbits = 16,
                             compression = WAV.WAVE_FORMAT_PCM)
            end
        end
        refs[id] = normal_level(joinpath(tmp, id), 0.0)
    end
    write_kit_toml(tmp, name, header, [(id, 0.0, refs[id], id in choke) for (id, _) in sources])
    write(joinpath(tmp, "LICENSE.txt"), license)
end

"""
Writes `dir/kit.toml` for a kit in folder format. `tracks`: `(id, pan, ref, choke)` with `ref` the
level of a normal hit (`normal_level`); the gain sets it to the snare target plus the balance in `BALANCE_DB`.
"""
function write_kit_toml(dir, name, header, tracks)
    io = IOBuffer()
    println(io, header)
    println(io, "name = \"$name\"")
    println(io, "# The samples carry their own dynamics, so hardly any extra level difference")
    println(io, "level_gain = [0.9, 1.0, 1.0]\n")
    println(io, "[tracks]")
    for (id, pan, ref, choke) in tracks
        g = SNARE_NORMAL_PEAK / ref * 10^(BALANCE_DB[id] / 20)
        ch = choke ? ", choke = 1" : ""
        println(io, rpad("$id ", 10), "= { folder = \"$id\", pan = $(round(pan, digits = 2)), ",
                "gain = $(round(g, digits = 2))$ch }")
    end
    write(joinpath(dir, "kit.toml"), String(take!(io)))
end

"""
Moves the finished kit from `tmp` to `dest`, replacing an older build. The old build is first
renamed to `<dest>.old` and only then deleted, so `dest` is never a half-deleted kit.
"""
function finish_build(tmp, dest, name; log = println)
    old = normpath(dest) * ".old"
    rm(old; recursive = true, force = true)
    isdir(dest) && mv(dest, old)
    mv(tmp, dest)
    rm(old; recursive = true, force = true)
    log(L("{1} fertig: {2}", name, normpath(dest)))
    return dest
end

"Fresh temporary build folder next to `dest` (removes leftovers of an interrupted build)."
function build_tmp(dest)
    mkpath(dirname(normpath(dest)))
    tmp = normpath(dest) * ".building"
    rm(tmp; recursive = true, force = true)
    rm(normpath(dest) * ".old"; recursive = true, force = true)
    mkpath(tmp)
    return tmp
end

"Downloads `url` to `file` (skipped if present), reporting progress about every 5 %."
function fetch_file(url, file, label; log = println)
    isfile(file) && return file
    mkpath(dirname(file))
    part = file * ".part"
    last = Ref(-1)
    progress(total, now) = begin
        total > 0 || return
        p = floor(Int, 100 * now / total)
        p >= last[] + 5 || return
        last[] = p
        log(L("{1} wird geladen: {2} % ({3} von {4} MB)", label, p, now ÷ 1_000_000, total ÷ 1_000_000))
    end
    Downloads.download(url, part; progress)
    mv(part, file; force = true)
    return file
end

"""
Extracts `archive` (zip, rar, tar) into `dir` (only `patterns` if given) with bsdtar from
LibArchive_jll. bsdtar writes into a hidden temporary folder in `dir`; only after it succeeded are
the files moved into place (merged with folders already there), so an interrupted or failed
extraction never leaves half-written files that a later build would take as complete.
"""
function extract(archive, dir, patterns = String[])
    mkpath(dir)
    tmp = joinpath(dir, "." * basename(archive) * ".extracting")
    rm(tmp; recursive = true, force = true)            # leftover of an interrupted extraction
    mkpath(tmp)
    try
        Base.run(`$(bsdtar()) -xf $archive -C $tmp $patterns`)
        merge_into!(tmp, dir)
    finally
        rm(tmp; recursive = true, force = true)
    end
    return dir
end

"Moves the contents of folder `src` into `dst`; folders present in both are merged."
function merge_into!(src, dst)
    for e in readdir(src)
        s, d = joinpath(src, e), joinpath(dst, e)
        isdir(s) && isdir(d) ? merge_into!(s, d) : mv(s, d; force = true)
    end
end

# ---------------------------------------------------------------------------
# CrocellKit (DrumGizmo), stereo mix by Henry Järvinen, CC BY 4.0
# ---------------------------------------------------------------------------

const CROCELL_URL = "https://drumgizmo.org/kits/CrocellKit/CrocellKit_Stereo_MIX.rar"
const CROCELL_MAP = [
    "Kick"     => ["KDrumR", "KDrumL"],   # both beaters of the double pedal as round-robin
    "Snare"    => ["Snare"],
    "Rim"      => ["SnareRim"],
    "HiHat"    => ["HihatClosed"],
    "HHOpen"   => ["HihatOpen"],
    "HHPedal"  => ["HihatPedal"],
    "Tom"      => ["Tom1"],
    "FloorTom" => ["FTom1"],
    "Ride"     => ["RideR"],
    "RideBell" => ["RideRBell"],
    "Crash"    => ["CrashL"],
]

"""
    build_crocell(; src = nothing, dest = joinpath(user_kit_dir(), "CrocellKit"), log = println)

Downloads (561 MB) and builds the CrocellKit. `src`: an already extracted `CrocellKit_Stereo_MIX`
folder (skips the download).
"""
function build_crocell(; src = nothing, dest = joinpath(user_kit_dir(), "CrocellKit"), log = println)
    if src === nothing
        cache = cache_dir()
        src = joinpath(cache, "CrocellKit_Stereo_MIX")
        if !all(i -> isdir(joinpath(src, i, "samples")), (i for (_, is) in CROCELL_MAP for i in is))
            rar = fetch_file(CROCELL_URL, joinpath(cache, "CrocellKit_Stereo_MIX.rar"), "CrocellKit"; log)
            log(L("{1} wird entpackt …", "CrocellKit"))
            rm(src; recursive = true, force = true)    # incomplete: extract anew (moved in as a whole)
            extract(rar, cache)
        end
    end
    loader(f) = () -> WAV.wavread(f; format = "double")[1:2]
    sources = map(CROCELL_MAP) do (id, insts)
        files = [joinpath(src, i, "samples", f) for i in insts for f in readdir(joinpath(src, i, "samples"))
                 if endswith(lowercase(f), ".wav")]
        id => [loader(f) for f in files]
    end
    build_kit(dest, "CrocellKit", sources; log,
        header = "# Built by DrumMachine.jl (build_crocell) – CrocellKit (DrumGizmo), stereo mix by Henry Järvinen",   # i18n-ok: name
        license = """
        CrocellKit (DrumGizmo) – stereo mix
        Kit: Crocell (crocell.dk), set up by Andreas; miking Jacob Olsen (JBOSound);
        sampled and prepared for DrumGizmo by Lars Muldjord / DrumGizmo team (drumgizmo.org).
        Stereo mix: Henry Järvinen.
        Source: $CROCELL_URL
        License: Creative Commons Attribution 4.0 International (CC BY 4.0)
                 https://creativecommons.org/licenses/by/4.0/

        Changes by DrumMachine.jl: selection of single recordings, resampling 48 -> 44.1 kHz,
        trimming/fading, conversion to 16 bit, level matching.
        """)
end

# ---------------------------------------------------------------------------
# Virtuosity Drums (Versilian Studios / Karoryfer), CC0
# Mix as in the vendor preset "Basic Kit": overheads (stereo) + kick mic + snare mic at equal level.
# ---------------------------------------------------------------------------

const VIRTUOSITY_URL = "https://github.com/sfzinstruments/virtuosity_drums/releases/download/v0.925/Virtuosity_Drums_v0.925.zip"
const VIRTUOSITY_MICS = ("oh", "kickmic", "snaremic")
const VIRTUOSITY_MAP = [   # track => (instrument folder, articulation)
    "Kick"     => ("kick", "snon"),          # kick with snare wires engaged
    "Snare"    => ("snare", "center"),
    "Rim"      => ("snare", "crossstick"),
    "HiHat"    => ("hh", "closed"),
    "HHOpen"   => ("hh", "open"),
    "HHPedal"  => ("hh", "pedal"),
    "Tom"      => ("htom", "center"),
    "FloorTom" => ("ltom", "center"),
    "Ride"     => ("ride", "ride"),
    "RideBell" => ("ride", "bell"),
    "Crash"    => ("crash", "crash"),
]

"Finds the `Samples` folder below `root`."
function virtuosity_samples(root)
    for (d, dirs, _) in walkdir(root)
        "Samples" in dirs && isdir(joinpath(d, "Samples", "oh")) && return joinpath(d, "Samples")
    end
    error(L("Kein Samples/oh unter {1} gefunden", root))
end

function read_flac(path)
    tmp = tempname() * ".wav"
    try
        Base.run(`$(flac()) -d -s -f -o $tmp $path`)
        y, fs = WAV.wavread(tmp; format = "double")
        return y, fs
    finally
        rm(tmp; force = true)
    end
end

"Mixes all available mics of a recording to stereo (mono mics panned center)."
function mix_mics(sdir, inst, stem)
    parts = Matrix{Float64}[]
    fs = 0.0
    for m in VIRTUOSITY_MICS
        f = joinpath(sdir, m, inst, "$(m)_$stem.flac")
        isfile(f) || continue
        y, fs = read_flac(f)
        push!(parts, size(y, 2) == 1 ? hcat(y, y) .* 0.7071 : y[:, 1:2])
    end
    isempty(parts) && error(L("Keine Aufnahme für {1}", stem))
    n = maximum(size.(parts, 1))
    out = zeros(n, 2)
    for p in parts
        out[1:size(p, 1), :] .+= p
    end
    return out, fs
end

"""
    build_virtuosity(; src = nothing, dest = joinpath(user_kit_dir(), "VirtuosityDrums"), log = println)

Downloads (1.2 GB) and builds the Virtuosity Drums jazz kit. `src`: an already extracted folder.
"""
function build_virtuosity(; src = nothing, dest = joinpath(user_kit_dir(), "VirtuosityDrums"), log = println)
    if src === nothing
        cache = cache_dir()
        src = joinpath(cache, "VirtuosityDrums")
        if !all(m -> isdir(joinpath(src, "Samples", m)), VIRTUOSITY_MICS)
            zip = fetch_file(VIRTUOSITY_URL, joinpath(cache, basename(VIRTUOSITY_URL)), "VirtuosityDrums"; log)
            log(L("{1} wird entpackt …", "VirtuosityDrums"))
            rm(src; recursive = true, force = true)    # incomplete: extract anew (moved in as a whole)
            extract(zip, src, ["Samples/$m/*" for m in VIRTUOSITY_MICS])
        end
    end
    sdir = virtuosity_samples(src)
    sources = map(VIRTUOSITY_MAP) do (id, (inst, art))
        prefix = "$(inst)_$(art)_vl"
        stems = sort(unique(replace(f, r"^oh_" => "", r"\.flac$" => "")
                            for f in readdir(joinpath(sdir, "oh", inst)) if startswith(f, "oh_$prefix")))
        isempty(stems) && error(L("Keine Dateien für {1}/{2}", inst, art))
        id => [() -> mix_mics(sdir, inst, s) for s in stems]
    end
    build_kit(dest, "VirtuosityDrums", sources; log,
        header = "# Built by DrumMachine.jl (build_virtuosity) – Virtuosity Drums (Versilian Studios / Karoryfer), CC0",
        license = """
        Virtuosity Drums – Contemporary Jazz Drum Kit
        Recorded at Virtuosity Musical Instruments, Boston (MA); drummer: Austin McMahon.
        Created by Versilian Studios LLC and Karoryfer Samples.
        Source: https://github.com/sfzinstruments/virtuosity_drums (release v0.925)
        License: CC0 1.0 (public domain) – credit appreciated, not required.
                 https://creativecommons.org/publicdomain/zero/1.0/

        Changes by DrumMachine.jl: mix of overhead, kick and snare mic (like the preset "Basic Kit"),
        selection of single recordings, resampling to 44.1 kHz, trimming/fading, conversion to
        16 bit, level matching.
        """)
end

# ---------------------------------------------------------------------------
# AVL Drumkits (Glen MacArthur, bandshed.net), CC BY-SA 3.0
# The original WAVs are copied unchanged (renamed into track folders); pan comes from the SFZ.
# ---------------------------------------------------------------------------

const AVL_BASE = "https://www.bandshed.net/sounds/AVLDrumkits_SFZ/"
const AVL_LICENSE = """
    Samples: Glen MacArthur, AVL Drumkits – http://www.bandshed.net/avldrumkits/
    License: Creative Commons Attribution-ShareAlike 3.0 (CC BY-SA 3.0)
             https://creativecommons.org/licenses/by-sa/3.0/
    """

"""
AVL kits: folder/display name, archive, track => file prefixes (several = round-robin, e.g. left
and right hand), tracks in the hi-hat choke group, description.
"""
const AVL_KITS = [
    (name = "RedZeppelin", zip = "RED_ZEPPELIN_2023_repack.zip",
     desc = "Ludwig kit with 26\" kick, Zildjian cymbals – big, open rock sound",
     map = ["Kick" => ["36-Ludwig-26-Kick"], "Snare" => ["38-Ludwig-14-Snare"],
            "Rim" => ["37-Ludwig-14-SideStick"], "HiHat" => ["42-Sabian-13-HatClosed"],
            "HHOpen" => ["46-Sabian-13-HatSemi"], "HHPedal" => ["44-Sabian-13-HatPedal"],
            "Tom" => ["45-Ludwig-14-Tom"], "FloorTom" => ["41-Ludwig-16-FloorTom"],
            "Ride" => ["51-Zildjian-24-Ride"], "RideBell" => ["53-Zildjian-24-RideBell"],
            "Crash" => ["49-Zildjian-20-Crash"]],
     choke = ("HiHat", "HHOpen", "HHPedal")),
    (name = "BlondeBop", zip = "BLONDE_BOP_SFZ.zip",
     desc = "TAMA bebop kit (18\" kick, 13\" snare) with sticks – jazz",
     map = ["Kick" => ["36-TAMA-18-Kick"], "Snare" => ["38-TAMA-13-Snare"],
            "Rim" => ["37-TAMA-13-SideStick"], "HiHat" => ["42-Zildjian-13-HatClosed"],
            "HHOpen" => ["46-Zildjian-13-HatSemi"], "HHPedal" => ["44-Zildjian-13-HatPedal"],
            "Tom" => ["45-TAMA-10-Tom"], "FloorTom" => ["41-TAMA-14-FloorTom"],
            "Ride" => ["51-SabianAAX-20-RideTip"], "RideBell" => ["53-SabianAAX-20-RideBell"],
            "Crash" => ["49-Paiste2002-16-Crash"]],
     choke = ("HiHat", "HHOpen", "HHPedal")),
    (name = "BlondeBopHotRods", zip = "BLONDE_BOP_HR_SFZ.zip",
     desc = "the same TAMA bebop kit played with Hot Rods – quiet, soft attack",
     map = ["Kick" => ["36-TAMA-18-Kick-HR"], "Snare" => ["38-TAMA-13-SnareCenter-HR"],
            "Rim" => ["37-TAMA-13-SnareSidestick-HR"], "HiHat" => ["42-Zildjian-13-HatClosed-HR"],
            "HHOpen" => ["46-Zildjian-12-HatSemi-HR"], "HHPedal" => ["44-Zildjian-13-HatPedal-HR"],
            "Tom" => ["45-TAMA-10-TomCenter-HR"], "FloorTom" => ["41-TAMA-14-FloorTomCenter-HR"],
            "Ride" => ["51-SabianAAX-20-RideTip-HR"], "RideBell" => ["53-SabianAAX-20-RideBell-HR"],
            "Crash" => ["49-Paiste2002-16-Crash-HR"]],
     choke = ("HiHat", "HHOpen", "HHPedal")),
    # percussion set: cajon instead of kick/snare, congas as toms, shaker/tambourine as hi-hat,
    # foot tambourine as hi-hat pedal, cowbell as ride
    (name = "BuskmansHoliday", zip = "BUSKMANS_HOLIDAY_SFZ.zip",
     desc = "percussion: cajon, congas, shaker, tambourines, claves, cowbell, cymbal",
     map = ["Kick" => ["36-Meinl-Cajon-Thump"],
            "Snare" => ["40-Meinl-Cajon-Slap-RH", "38-Meinl-Cajon-Slap-LH"],
            "Rim" => ["48-Claves"], "HiHat" => ["42-GonBops-Triple-Shaker"],
            "HHOpen" => ["44-Shake-Tambourine"], "HHPedal" => ["46-GP-Bump-Tambourine"],
            "Tom" => ["47-Meinl-Conga-Small-RH", "45-Meinl-Conga-Small-LH"],
            "FloorTom" => ["43-Meinl-Conga-Large-RH", "41-Meinl-Conga-Large-LH"],
            "Ride" => ["51-LP-Cowbell"], "RideBell" => ["50-Paiste-2002-16-CymbalBell"],
            "Crash" => ["49-Paiste-2002-16-Cymbal"]],
     choke = ()),
]

"Pan per sample prefix from an SFZ file (`pan` of the group or region, -100…100 -> -1…1)."
function sfz_pans(sfz)
    pans = Dict{String,Float64}()
    gpan = 0.0
    for line in eachline(sfz)
        line = strip(replace(line, r"//.*$" => ""))
        p = match(r"\bpan=(-?[\d.]+)", line)
        if startswith(line, "<group>")
            gpan = p === nothing ? 0.0 : parse(Float64, p[1]) / 100
        elseif startswith(line, "<region>")
            s = match(r"\bsample=(\S+?\.wav)", line)
            s === nothing && continue
            prefix = replace(basename(s[1]), r"-\d+\.wav$" => "")
            pans[prefix] = p === nothing ? gpan : parse(Float64, p[1]) / 100
        end
    end
    return pans
end

"Peak of a sample as the engine plays it at `pan` (stereo: balance, mono: equal-power law)."
function played_peak(s::Sample, pan)
    p = clamp(pan, -1, 1)
    isstereo(s) && return max(min(1, 1 - p) * maximum(abs, s.l), min(1, 1 + p) * maximum(abs, s.r))
    θ = (p + 1) * π / 4
    return max(cos(θ), sin(θ)) * maximum(abs, s.l)
end

"""
Level of a normal hit of a track folder: median `played_peak` of the normal layers, loaded as
at runtime (onset trimmed). The whole sample counts, so pre-noise (hi-hat pedal) or a late swell
(open hi-hat with rods) does not distort the balance.
"""
function normal_level(folder, pan)
    layers = load_folder_layers(folder)
    pk = sort([played_peak(s, pan) for l in level_layers(2, length(layers)) for s in layers[l]])
    return pk[cld(length(pk), 2)]
end

"""
    build_avl(spec; src = nothing, dest = joinpath(user_kit_dir(), spec.name), log = println)

Downloads (about 20 MB) and installs one of the `AVL_KITS`. `src`: already extracted SFZ folder.
"""
function build_avl(spec; src = nothing, dest = joinpath(user_kit_dir(), spec.name), log = println)
    if src === nothing
        cache = cache_dir()
        src = joinpath(cache, replace(spec.zip, r"\.zip$" => ""))
        if !isdir(src)                                 # the folder is moved in only when complete
            zip = fetch_file(AVL_BASE * spec.zip, joinpath(cache, spec.zip), spec.name; log)
            log(L("{1} wird entpackt …", spec.name))
            extract(zip, cache)
        end
    end
    sfz = only(f for f in readdir(src; join = true) if endswith(lowercase(f), ".sfz"))
    pans = sfz_pans(sfz)
    tmp = build_tmp(dest)
    try
        build_avl_files(tmp, spec, src, pans)
    catch
        rm(tmp; recursive = true, force = true)       # no half-built folder left behind
        rethrow()
    end
    finish_build(tmp, dest, spec.name; log)
end

function build_avl_files(tmp, spec, src, pans)
    tracks = map(spec.map) do (id, prefixes)
        mkpath(joinpath(tmp, id))
        for (rr, p) in enumerate(prefixes)
            l = 0
            while isfile(joinpath(src, "$p-$(l + 1).wav"))
                l += 1
                cp(joinpath(src, "$p-$l.wav"), joinpath(tmp, id, "$l-$rr.wav"))
            end
            l == 0 && error(L("Keine Dateien für {1}/{2}", spec.name, p))
        end
        pan = sum(get(pans, p, 0.0) for p in prefixes) / length(prefixes)
        (id, pan, normal_level(joinpath(tmp, id), pan), id in spec.choke)
    end
    write_kit_toml(tmp, spec.name, "# Built by DrumMachine.jl (build_avl) – AVL Drumkits \"$(spec.name)\" by Glen MacArthur",
                   tracks)
    write(joinpath(tmp, "LICENSE.txt"), """
        AVL Drumkits – "$(spec.name)": $(spec.desc)
        $AVL_LICENSE
        Source: $(AVL_BASE)$(spec.zip)

        Changes by DrumMachine.jl: none to the audio. A selection of the original WAV files, renamed
        into one folder per track (<layer>-<round-robin>.wav); kit.toml written for DrumMachine.jl.
        """)
end

# ---------------------------------------------------------------------------
# DrumGizmo kits (multi-mic recordings): the mics are mixed down to stereo here.
# ---------------------------------------------------------------------------

"Attributes of an XML tag as a Dict."
xml_attrs(s) = Dict(m[1] => m[2] for m in eachmatch(r"([\w:-]+)\s*=\s*\"([^\"]*)\"", s))

"""
    dg_instruments(kitxml) -> Dict(name => (file, channelmap))

Instruments of a DrumGizmo drumkit file: instrument file (absolute) and the channel map
(instrument channel => kit channel).
"""
function dg_instruments(kitxml)
    xml = read(kitxml, String)
    out = Dict{String,Tuple{String,Dict{String,String}}}()
    for m in eachmatch(r"<instrument\b([^>]*?)(/>|>(.*?)</instrument>)"s, xml)
        a = xml_attrs(m[1])
        haskey(a, "file") || continue
        cmap = Dict{String,String}()
        m[3] === nothing || for c in eachmatch(r"<channelmap\b([^>]*)>", m[3])
            ca = xml_attrs(c[1])
            cmap[ca["in"]] = ca["out"]
        end
        out[a["name"]] = (normpath(joinpath(dirname(kitxml), a["file"])), cmap)
    end
    return out
end

"""
    dg_samples(instfile, cmap) -> Vector{Vector{Tuple{String,String,Int}}}

Recordings of a DrumGizmo instrument: per recording a list of (kit channel, wav file, channel
in that file).
"""
function dg_samples(instfile, cmap)
    xml = read(instfile, String)
    map(eachmatch(r"<sample\b[^>]*>(.*?)</sample>"s, xml)) do m
        map(eachmatch(r"<audiofile\b([^>]*)>", m[1])) do af
            a = xml_attrs(af[1])
            ch = get(cmap, a["channel"], a["channel"])
            (ch, normpath(joinpath(dirname(instfile), a["file"])), parse(Int, get(a, "filechannel", "1")))
        end
    end
end

"""
    dg_mix(audiofiles, mix; polarity) -> (stereo matrix, fs)

Mixes one recording to stereo. `mix`: kit channel => (gain, pan) (pan -1 left … +1 right, from the
drummer's view); channels not in `mix` are dropped (trigger channels). `polarity`: pairs
`a => b`; channel `a` is inverted if it is out of phase with `b` (snare bottom vs. top mic).
"""
function dg_mix(afs, mix; polarity = Pair{String,String}[])
    files = Dict{String,Tuple{Matrix{Float64},Float64}}()
    rd(f) = get!(() -> (r = WAV.wavread(f; format = "double"); (r[1], Float64(r[2]))), files, f)
    chans = Dict{String,Vector{Float64}}()
    fs = 0.0
    for (ch, f, fc) in afs
        haskey(mix, ch) || continue
        y, fs = rd(f)
        chans[ch] = y[:, fc]
    end
    isempty(chans) && error(L("Keine Aufnahme für {1}", join(first.(afs), ", ")))
    for (a, b) in polarity
        (haskey(chans, a) && haskey(chans, b)) || continue
        n = min(length(chans[a]), length(chans[b]), round(Int, 0.05fs))
        sum(view(chans[a], 1:n) .* view(chans[b], 1:n)) < 0 && (chans[a] = -chans[a])
    end
    n = maximum(length, values(chans))
    out = zeros(n, 2)
    for (ch, x) in chans
        g, p = mix[ch]
        out[1:length(x), 1] .+= (g * min(1.0, 1 - p)) .* x
        out[1:length(x), 2] .+= (g * min(1.0, 1 + p)) .* x
    end
    return out, fs
end

# Mixes: channel => (gain, pan). Overheads carry the stereo picture, close mics add punch,
# room mics a little space. Drummer's view: hi-hat left, floor tom right.
const DG_DRS_MIX = Dict(
    "OHL" => (1.0, -0.8), "OHR" => (1.0, 0.8), "AmbL" => (0.4, -0.7), "AmbR" => (0.4, 0.7),
    "Kdrum_back" => (0.7, 0.0), "Kdrum_front" => (0.4, 0.0), "Snare_top" => (0.7, -0.1),
    "Snare_bottom" => (0.2, -0.1), "Hihat" => (0.25, -0.5), "Ride" => (0.25, 0.5),
    "Tom1" => (0.6, -0.1), "Tom2" => (0.6, 0.3), "Tom3" => (0.6, 0.45))
const DG_MULDJORD_MIX = Dict(
    "OHL" => (1.0, -0.8), "OHR" => (1.0, 0.8), "AmbL" => (0.4, -0.7), "AmbR" => (0.4, 0.7),
    "KdrumL" => (0.6, -0.05), "KdrumR" => (0.6, 0.05), "Snare_top" => (0.7, -0.1),
    "Snare_bottom" => (0.2, -0.1), "Hihat" => (0.25, -0.5), "RideL" => (0.2, -0.6),
    "RideR" => (0.25, 0.6), "Tom1" => (0.6, -0.2), "Tom2" => (0.6, 0.0), "Tom3" => (0.6, 0.3),
    "Tom4" => (0.6, 0.45))
const DG_AASI_MIX = Dict(
    "OHL" => (1.0, -0.8), "OHR" => (1.0, 0.8), "AmbL" => (0.4, -0.7), "AmbR" => (0.4, 0.7),
    "KdrumL" => (0.6, -0.05), "KdrumR" => (0.6, 0.05), "Snare_top" => (0.7, -0.1),
    "Snare_bottom" => (0.2, -0.1), "Hihat" => (0.25, -0.5), "Ride" => (0.25, 0.5),
    "Tom1" => (0.6, -0.2), "Tom2" => (0.6, 0.0), "Tom3" => (0.6, 0.3), "Tom4" => (0.6, 0.45))
# ShittyKit: the room pair is an unprocessed M/S couple whose mid/side order is unknown, so it is
# used in mono (no phase problems either way).
const DG_SHITTY_MIX = Dict(
    "OH-L" => (1.0, -0.8), "OH-R" => (1.0, 0.8), "Room-L" => (0.3, 0.0), "Room-R" => (0.3, 0.0),
    "kick" => (0.7, 0.0), "snare" => (0.7, -0.1), "Tom" => (0.6, -0.1), "Floor" => (0.6, 0.4))
const DG_STEREO_MIX = Dict("L" => (1.0, -0.6), "R" => (1.0, 0.6))

const DG_SNARE_POLARITY = ["Snare_bottom" => "Snare_top"]

# CrocellKit, multi-mic version: several mixes of the same recordings. Channels: kick inside /
# outside the drum, snare top / bottom, hi-hat, ride, toms, overheads L/C/R, room L/R.
crocell_mix(; close, oh, amb, hh = 0.3close, ride = 0.3close) = Dict(
    "KDrumInside" => (close, 0.0), "KDrumOutside" => (0.5close, 0.0),
    "SnareTop" => (close, -0.1), "SnareBottom" => (0.3close, -0.1),
    "Tom1" => (0.9close, -0.15), "Tom2" => (0.9close, 0.05), "FTom1" => (0.9close, 0.35),
    "FTom2" => (0.9close, 0.5), "Hihat" => (hh, -0.5), "Ride" => (ride, 0.5),
    "OHLeft" => (oh, -0.8), "OHRight" => (oh, 0.8), "OHCenter" => (0.5oh, 0.0),
    "AmbLeft" => (amb, -0.9), "AmbRight" => (amb, 0.9))
# overheads only (plus a touch of kick and room): the kit as heard from above, like old records
const CROCELL_VINTAGE_MIX = Dict(
    "OHLeft" => (1.0, -0.6), "OHRight" => (1.0, 0.6), "OHCenter" => (0.7, 0.0),
    "KDrumOutside" => (0.35, 0.0), "AmbLeft" => (0.2, -0.8), "AmbRight" => (0.2, 0.8))

"""
Lo-fi processing for a prepared recording: narrow stereo, band limit 70 Hz – 5 kHz, tape-like
saturation, 12-bit grit. Keeps the peak at most 0.95.
"""
function lofi(y::AbstractMatrix)
    m = (y[:, 1] .+ y[:, 2]) ./ 2
    sd = (y[:, 1] .- y[:, 2]) ./ 2 .* 0.3
    out = similar(y)
    for (c, x) in enumerate((m .+ sd, m .- sd))
        highpass!(x, 70); lowpass!(x, 5000); lowpass!(x, 7000)
        x .= tanh.(2.5 .* x) ./ tanh(2.5)
        crush!(x, 12, 1)
        out[:, c] .= x
    end
    pk = maximum(abs, out)
    return pk > 0.95f0 ? out .* Float32(0.95 / pk) : out     # only lower: layers keep their dynamics
end
const DG_URL = "https://drumgizmo.org/kits/"
const DG_LICENSE = """
    License: Creative Commons Attribution 4.0 International (CC BY 4.0)
             https://creativecommons.org/licenses/by/4.0/
    """

"""
DrumGizmo kits: name, archive URL, folder inside the archive, drumkit file, track => instruments
(several = round-robin), mix, credit. Tracks without a fitting instrument use the nearest one
(noted in the comments).
"""
const DG_KITS = [
    (name = "DRSKit", url = DG_URL * "DRSKit/DRSKit2_1.zip", root = "DRSKit", xml = "DRSKit_full.xml",
     map = ["Kick" => ["Kdrum_with_contact"], "Snare" => ["Snare"], "Rim" => ["Snare_rim"],
            "HiHat" => ["Hihat_closed"], "HHOpen" => ["Hihat_open"], "HHPedal" => ["Hihat_foot"],
            "Tom" => ["Tom1"], "FloorTom" => ["Tom3"], "Ride" => ["Ride_tip"],
            "RideBell" => ["Ride_shank_bell"], "Crash" => ["Crash_left_shank"]],
     mix = DG_DRS_MIX, polarity = DG_SNARE_POLARITY,
     credit = """
        DRSKit 2.1 (DrumGizmo) – handmade kit by Jes Eiler, DRSDrums (drsdrums.dk), Paiste cymbals.
        Setup, miking, sampling: Deva & Lars Muldjord; edited by Lars Muldjord (drumgizmo.org).
        """),
    (name = "MuldjordKit", url = DG_URL * "MuldjordKit/MuldjordKit3.zip", root = "MuldjordKit3",
     xml = "MuldjordKit3.xml",
     # no hi-hat pedal recordings: the closed hi-hat stands in; side stick = "SnareRest"
     map = ["Kick" => ["KdrumL", "KdrumR"], "Snare" => ["Snare"], "Rim" => ["SnareRest"],
            "HiHat" => ["HihatClosed"], "HHOpen" => ["HihatOpen"], "HHPedal" => ["HihatClosed"],
            "Tom" => ["Tom1"], "FloorTom" => ["Tom4"], "Ride" => ["RideR"],
            "RideBell" => ["RideRBell"], "Crash" => ["CrashL"]],
     mix = DG_MULDJORD_MIX, polarity = DG_SNARE_POLARITY,
     credit = """
        MuldjordKit 3 (DrumGizmo) – Tama Superstar kit, recorded 2010 by Lars Muldjord
        for the Sepulchrum debut album; prepared for DrumGizmo by Lars Muldjord (drumgizmo.org).
        """),
    (name = "Aasimonster", url = DG_URL * "Aasimonster/aasimonster2_1.zip", root = "aasimonster2",
     xml = "aasimonster.xml",
     # side stick = rim shot (no cross-stick recordings); pedal = "hihat_closed3" as in the kit's midimap
     map = ["Kick" => ["kick_l", "kick_r"], "Snare" => ["snare_on_center"], "Rim" => ["snare_rim_shot"],
            "HiHat" => ["hihat_closed1"], "HHOpen" => ["hihat_open"], "HHPedal" => ["hihat_closed3"],
            "Tom" => ["tom_1"], "FloorTom" => ["tom_4"], "Ride" => ["ride"],
            "RideBell" => ["ride_bell2"], "Crash" => ["crash1"]],
     mix = DG_AASI_MIX, polarity = DG_SNARE_POLARITY,
     credit = """
        The Aasimonster 2.1 (DrumGizmo) – death metal kit used for the record "Rise of the Rotten"
        by DIE (executionroom.com); converted to the 2.0 format by Chaot4 (drumgizmo.org).
        """),
    (name = "ShittyKit", url = DG_URL * "ShittyKit/ShittyKit1_2.zip", root = "ShittyKit",
     xml = "ShittyKit.xml",
     map = ["Kick" => ["kick"], "Snare" => ["snare-Dyn-RH", "snare-Dyn-LH"], "Rim" => ["snare-RmClk"],
            "HiHat" => ["HH-closed"], "HHOpen" => ["HH-open"], "HHPedal" => ["HH-pdl"],
            "Tom" => ["Tom-RH", "Tom-LH"], "FloorTom" => ["Floor-RH", "Floor-LH"], "Ride" => ["ride"],
            "RideBell" => ["ride-bell"], "Crash" => ["Crash1"]],
     mix = DG_SHITTY_MIX, polarity = Pair{String,String}[],
     credit = """
        ShittyKit 1.2 (DrumGizmo) by Herr Doktor Sardonicus (sardonicus@free.fr) – Stagg Gia kit
        (18" kick, 14x5 snare, 12" tom, 14" floor tom), 8 channels. The original archive with the
        unchanged WAV and XML files is available at the source below.
        """),
    # same recordings as the CrocellKit stereo mix, but from the single mics: own mixes
    (name = "CrocellMixes", url = DG_URL * "CrocellKit/CrocellKit1_1.zip", root = "CrocellKit",
     xml = "CrocellKit_full.xml",
     map = ["Kick" => ["KDrumL", "KDrumR"], "Snare" => ["Snare"], "Rim" => ["SnareRim"],
            "HiHat" => ["HihatClosed"], "HHOpen" => ["HihatOpen"], "HHPedal" => ["HihatPedal"],
            "Tom" => ["Tom1"], "FloorTom" => ["FTom1"], "Ride" => ["RideR"],
            "RideBell" => ["RideRBell"], "Crash" => ["CrashL"]],
     polarity = ["SnareBottom" => "SnareTop", "KDrumOutside" => "KDrumInside"],
     variants = [
        (name = "CrocellClose", post = nothing, mix = crocell_mix(close = 1.0, oh = 0.35, amb = 0.0, hh = 0.6, ride = 0.5),
         desc = "close mics up front, little overhead, no room – dry and direct"),
        (name = "CrocellStudio", post = nothing, mix = crocell_mix(close = 0.8, oh = 0.8, amb = 0.15),
         desc = "close mics and overheads balanced, a little room – studio sound"),
        (name = "CrocellRoom", post = nothing, mix = crocell_mix(close = 0.5, oh = 0.7, amb = 1.2),
         desc = "lots of room mics – big, live"),
        (name = "CrocellVintage", post = nothing, mix = CROCELL_VINTAGE_MIX,
         desc = "overheads only plus a touch of kick and room – natural, like old records"),
        (name = "CrocellLoFi", post = lofi, mix = crocell_mix(close = 0.8, oh = 0.8, amb = 0.15),
         desc = "studio mix, narrowed, band-limited (70 Hz – 5 kHz), saturated, 12 bit – hip-hop"),
     ],
     credit = """
        CrocellKit 1.1 (DrumGizmo) – kit of the Danish metal band Crocell (crocell.dk), set up by
        Andreas; mic setup Jacob Olsen (JBOSound); sampled and prepared by Lars Muldjord (drumgizmo.org).
        """),
    # fun kit of everyday objects; there are no cymbals, so cup/glass/clap stand in
    (name = "Sommerhack", url = "http://www.drumgizmo.org/kits/sommerhack-kit.zip", root = "sommerhack-kit",
     xml = "sommerhack-kit.xml",
     map = ["Kick" => ["log"], "Snare" => ["clap"], "Rim" => ["snap"], "HiHat" => ["cup"],
            "HHOpen" => ["glass"], "HHPedal" => ["camera"], "Tom" => ["chair"], "FloorTom" => ["log"],
            "Ride" => ["cup"], "RideBell" => ["glass"], "Crash" => ["clap"]],
     mix = DG_STEREO_MIX, polarity = Pair{String,String}[],
     credit = """
        Sommerhack 2016 kit (DrumGizmo) – everyday objects (log, clap, cup, glass, chair, camera …)
        recorded at the Sommerhack 2016 hacker camp in Denmark with two SM57.
        """),
]

"""
    build_drumgizmo(spec; src = nothing, dest = joinpath(user_kit_dir(), spec.name), log = println)

Downloads one of the `DG_KITS`, extracts only the instruments needed and mixes the mics to stereo.
`src`: an already extracted kit folder (the one containing the drumkit XML). A downloaded archive
larger than 1 GB is deleted after a successful build.
"""
function build_drumgizmo(spec; src = nothing, dest = joinpath(user_kit_dir(), spec.name), log = println)
    vs = dg_variants(spec)
    length(vs) == 1 || (dest = user_kit_dir())             # several mixes: one folder per variant
    given = src !== nothing
    cache = cache_dir()
    given || (src = joinpath(cache, spec.root))
    archive = joinpath(cache, basename(spec.url))
    function unpack(patterns)
        given && error(L("Dateien fehlen in {1}", src))
        fetch_file(spec.url, archive, spec.name; log)
        log(L("{1} wird entpackt …", spec.name))
        extract(archive, cache, patterns)
    end
    isfile(joinpath(src, spec.xml)) || unpack(["$(spec.root)/*.xml"])   # kit and instrument files
    insts = dg_instruments(joinpath(src, spec.xml))
    recs = map(spec.map) do (id, names)
        id => [afs for nm in names
                   for afs in (haskey(insts, nm) ? dg_samples(insts[nm]...) :
                               error(L("Instrument {1} fehlt in {2}", nm, spec.xml)))]
    end
    # only the recordings of the instruments used
    wavs = unique(f for (_, rs) in recs for afs in rs for (_, f, _) in afs)
    missing_wavs = filter(!isfile, wavs)
    isempty(missing_wavs) || unpack(relpath.(missing_wavs, cache))
    for v in vs
        sources = [id => Function[() -> dg_mix(afs, v.mix; polarity = spec.polarity) for afs in rs]
                   for (id, rs) in recs]
        build_kit(length(vs) == 1 ? dest : joinpath(dest, v.name), v.name, sources; log, post = v.post,
            header = "# Built by DrumMachine.jl (build_drumgizmo) – $(v.name) (DrumGizmo), stereo mix by DrumMachine.jl",
            license = """
            $(spec.credit)$(isempty(v.desc) ? "" : "\nThis variant: " * v.desc * "\n")
            Source: $(spec.url)
            $DG_LICENSE
            Changes by DrumMachine.jl: stereo mix of the microphone channels$(v.post === nothing ? "" : " plus processing (see above)"),
            selection of single recordings, resampling to 44.1 kHz, trimming/fading, conversion to
            16 bit, level matching.
            """)
    end
    if !given && isfile(archive) && filesize(archive) > 1_000_000_000
        rm(archive; force = true)
        rm(src; recursive = true, force = true)
    end
    return dest
end

"Mixes of a DrumGizmo kit spec: its `variants`, or a single one from `name` and `mix`."
dg_variants(spec) = hasproperty(spec, :variants) ? spec.variants :
                    [(name = spec.name, mix = spec.mix, post = nothing, desc = "")]

# ---------------------------------------------------------------------------
# Download on request (kit menu), optionally automatic
# ---------------------------------------------------------------------------

"""
Kits that can be downloaded and built: (name, size label, build function, auto, kits it
provides – several for the mixes of one recording). All of them appear in the kit menu as
"(download, size)" and are built when chosen. With the setting `auto_kits = true` the kits with
`auto = true` are fetched in the background at start; the large ones always need to be chosen.
"""
dgkit(name) = (; kw...) -> build_drumgizmo(DG_KITS[findfirst(k -> k.name == name, DG_KITS)]; kw...)
const DOWNLOADABLE_KITS = vcat(
    [(spec.name, "20 MB", (; kw...) -> build_avl(spec; kw...), true, [spec.name]) for spec in AVL_KITS],
    [("Sommerhack", "12 MB", dgkit("Sommerhack"), true, ["Sommerhack"]),
     ("ShittyKit", "370 MB", dgkit("ShittyKit"), true, ["ShittyKit"]),
     ("CrocellKit", "561 MB", build_crocell, true, ["CrocellKit"]),
     ("VirtuosityDrums", "1,2 GB", build_virtuosity, true, ["VirtuosityDrums"]),
     ("DRSKit", "2,8 GB", dgkit("DRSKit"), false, ["DRSKit"]),
     ("MuldjordKit", "2,5 GB", dgkit("MuldjordKit"), false, ["MuldjordKit"]),
     ("Aasimonster", "2,4 GB", dgkit("Aasimonster"), false, ["Aasimonster"]),
     ("CrocellMixes", "5,6 GB", dgkit("CrocellMixes"), false,
      [v.name for v in dg_variants(DG_KITS[findfirst(k -> k.name == "CrocellMixes", DG_KITS)])])])

"Downloadable kits of which at least one provided kit is not installed yet."
function missing_kits()
    have = Set(e.name for e in kit_entries())
    return [k for k in DOWNLOADABLE_KITS if !all(in(have), k[5])]
end

"""
Downloadable kits offered in the kit menu as "(download, size)": all missing ones, except kits
marked `auto` that the automatic download (`auto_kits = true`) is building right now. A kit whose
automatic download failed is offered again, so it can be retried from the menu.
"""
function on_demand_kits()
    auto = auto_kits_enabled()
    return [k for k in missing_kits() if !(auto && k[4] && kit_building(k[1]))]
end

"""
The automatic download is off by default: nothing is downloaded until a kit is chosen in the kit
menu. The setting `auto_kits = true` switches it on; the environment variable
`DRUMMACHINE_NO_KIT_DOWNLOAD` keeps it off regardless of the setting.
"""
auto_kits_enabled() = !haskey(ENV, "DRUMMACHINE_NO_KIT_DOWNLOAD") && get(load_settings(), "auto_kits", false) === true

"Kits being built right now in this process (so a kit is never built twice at the same time)."
const KITS_BUILDING = Set{String}()
const KITS_BUILDING_LOCK = ReentrantLock()

"Is kit `name` being built in this process right now? (Reads `KITS_BUILDING` under its lock.)"
kit_building(name::AbstractString) = lock(() -> name in KITS_BUILDING, KITS_BUILDING_LOCK)

"Lock files held by this process right now (see [`with_pidlock`](@ref))."
const PIDLOCKS_HELD = Set{String}()
const PIDLOCKS_HELD_LOCK = ReentrantLock()

"""
    with_pidlock(f, path) -> Bool

Runs `f()` while holding the lock file `path`, which also guards against other processes (two
app windows, or the app and a script in tools/). The file holds the process id; a file left by a
process that no longer runs is taken over. Returns `false` without running `f` if a running
process holds the lock, `true` after `f` ran.
"""
function with_pidlock(f, path)
    path = abspath(path)
    mkpath(dirname(path))
    flags = Base.Filesystem.JL_O_WRONLY | Base.Filesystem.JL_O_CREAT | Base.Filesystem.JL_O_EXCL
    for _ in 1:2
        fd = try
            Base.Filesystem.open(path, flags, 0o644)
        catch e
            e isa Base.IOError && e.code == Base.UV_EEXIST || rethrow()
            nothing
        end
        if fd === nothing
            pidlock_stale(path) || return false
            rm(path; force = true)                      # left by a process that ended: take over
            continue
        end
        lock(() -> push!(PIDLOCKS_HELD, path), PIDLOCKS_HELD_LOCK)
        try
            write(fd, string(getpid())); close(fd)
            f()
        finally
            rm(path; force = true)
            lock(() -> delete!(PIDLOCKS_HELD, path), PIDLOCKS_HELD_LOCK)
        end
        return true
    end
    return false
end

"""
Is the lock file `path` left over? Yes if it is older than the last boot (the pid may belong to
another process by now), if its process no longer runs, or if it has the pid of this process
but this process does not hold it (left by an earlier process with the same pid).
"""
function pidlock_stale(path)
    path = abspath(path)
    mtime(path) < time() - Sys.uptime() && return true       # written before the last boot
    pid = tryparse(Int, strip(try read(path, String) catch; "" end))
    pid === nothing && return time() - mtime(path) > 60      # pid not written (yet): stale after a minute
    pid == getpid() && return !lock(() -> path in PIDLOCKS_HELD, PIDLOCKS_HELD_LOCK)
    return ccall(:uv_kill, Cint, (Cint, Cint), pid, 0) == Base.UV_ESRCH   # signal 0: does it exist?
end

"""
    kit_lock(f, name) -> Bool

Runs `f()` (download, extract, build of kit `name`) under a lock shared by all processes, so two
processes never write the same `.part`, `.extracting` or `.building` files. `false` if another
running process builds the kit.
"""
kit_lock(f, name::AbstractString) = with_pidlock(f, joinpath(cache_dir(), name * ".lock"))

"""
Builds one downloadable kit (in the calling task); false if it is already being built (in this
or another process). `done(name)` is called after the attempt, also after an error, so the kit
menu can be refreshed.
"""
function fetch_kit(kit, post::Function, done::Function)
    name, size, build, _ = kit
    lock(() -> name in KITS_BUILDING ? false : (push!(KITS_BUILDING, name); true), KITS_BUILDING_LOCK) || return false
    ran = true
    try
        ran = kit_lock(name) do
            post(L("Kit {1} wird geladen ({2}, läuft im Hintergrund) …", name, size))
            build(; log = post)
        end
        ran || post(L("Kit {1} wird schon von einem anderen DrumMachine-Prozess geladen.", name))
    catch e
        post(L("Kit {1} konnte nicht geladen werden: {2}", name, sprint(showerror, e)))
        @warn L("Kit {1} konnte nicht geladen werden", name) exception = e
    finally
        lock(() -> delete!(KITS_BUILDING, name), KITS_BUILDING_LOCK)
        done(name)
    end
    return ran
end

"""
    fetch_kit!(name, post, done) -> Union{Task,Nothing}

Builds the downloadable kit `name` on a background thread (chosen in the kit menu).
"""
function fetch_kit!(name::AbstractString, post::Function, done::Function)
    k = findfirst(x -> x[1] == name, DOWNLOADABLE_KITS)
    k === nothing && return nothing
    return Threads.@spawn fetch_kit(DOWNLOADABLE_KITS[k], post, done)
end

"""
    auto_fetch_kits!(post, done) -> Union{Task,Nothing}

Builds all missing kits marked `auto` one after another on a background thread. `post(msg)` gets
progress and error messages, `done(name)` is called after each kit (built or failed). A kit that
was installed from the kit menu in the meantime is skipped. Returns `nothing` if there is nothing
to do or the automatic download is off (the default, see `auto_kits_enabled`).
"""
function auto_fetch_kits!(post::Function, done::Function)
    auto_kits_enabled() || return nothing
    todo = [k for k in missing_kits() if k[4]]
    isempty(todo) && return nothing
    return Threads.@spawn for k in todo
        have = Set(e.name for e in kit_entries())
        all(in(have), k[5]) && continue
        fetch_kit(k, post, done)
    end
end
