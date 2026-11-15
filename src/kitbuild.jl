# Building the large sample kits (CrocellKit, VirtuosityDrums) from their public downloads.
# Runs inside the package so it also works for an installed (read-only) package: archives go to
# the cache directory, built kits to the user's data directory. The scripts in tools/ call this.
#
# Steps per kit: download (with progress), extract (bsdtar, or unrar/unzip), pick velocity layers by
# measured level, resample to 44.1 kHz, trim, write 16-bit WAVs, calibrate the balance.

import Downloads
using FLAC_jll: flac

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
(one recording, stereo or mono). Writes `dest/<track>/<layer>-<rr>.wav`, `kit.toml`, `LICENSE.txt`.
The kit is built in a temporary folder next to `dest` and moved into place at the end, so an
interrupted build never leaves a half-finished kit behind.
"""
function build_kit(dest, name, sources; header::AbstractString, license::AbstractString,
                   choke = ("HiHat", "HHOpen", "HHPedal"), log = println)
    mkpath(dirname(normpath(dest)))
    tmp = normpath(dest) * ".building"
    isdir(tmp) && rm(tmp; recursive = true)
    mkpath(tmp)
    refs = Dict{String,Float64}()
    for (k, (id, loaders)) in enumerate(sources)
        log(L("{1}: Instrument {2}/{3} ({4})", name, k, length(sources), id))
        peaks = [attack_peak(ld()...) for ld in loaders]
        db = 20 .* log10.(peaks ./ maximum(peaks))
        mkpath(joinpath(tmp, id))
        normal = Float64[]
        for b in 1:length(BIN_EDGES)-1
            lo, hi = BIN_EDGES[b], BIN_EDGES[b+1]
            idx = [i for i in eachindex(db) if lo <= db[i] < hi]
            isempty(idx) && (idx = sortperm(abs.(db .- (lo + hi) / 2))[1:1])   # empty layer: nearest recording
            idx = sort(idx; by = i -> db[i])
            pick = length(idx) <= MAX_RR ? idx : idx[round.(Int, range(1, length(idx), length = MAX_RR))]
            for (rr, i) in enumerate(unique(pick))
                y, fs = loaders[i]()
                out = prepare_sample(y, fs, MAXLEN[id])
                pcm = round.(Int16, clamp.(out, -1, 1) .* 32767)
                WAV.wavwrite(pcm, joinpath(tmp, id, "$b-$rr.wav"); Fs = SR, nbits = 16,
                             compression = WAV.WAVE_FORMAT_PCM)
                b in (3, 4) && push!(normal, attack_peak(out, SR))
            end
        end
        refs[id] = sort(normal)[cld(length(normal), 2)]
    end
    io = IOBuffer()
    println(io, header)
    println(io, "name = \"$name\"")
    println(io, "# The samples carry their own dynamics, so hardly any extra level difference")
    println(io, "level_gain = [0.9, 1.0, 1.0]\n")
    println(io, "[tracks]")
    for (id, _) in sources
        g = SNARE_NORMAL_PEAK / refs[id] * 10^(BALANCE_DB[id] / 20)
        ch = id in choke ? ", choke = 1" : ""
        println(io, rpad("$id ", 10), "= { folder = \"$id\", pan = 0.0, gain = $(round(g, digits = 2))$ch }")
    end
    write(joinpath(tmp, "kit.toml"), String(take!(io)))
    write(joinpath(tmp, "LICENSE.txt"), license)
    isdir(dest) && rm(dest; recursive = true)
    mv(tmp, dest)
    log(L("{1} fertig: {2}", name, normpath(dest)))
    return dest
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

"Extracts `archive` into `dir` (only `patterns` if given) with bsdtar, or the named fallback tool."
function extract(archive, dir, patterns = String[]; fallback::Symbol)
    mkpath(dir)
    if Sys.which("bsdtar") !== nothing
        Base.run(`bsdtar -xf $archive -C $dir $patterns`)
    elseif fallback == :unrar && Sys.which("unrar") !== nothing
        Base.run(`unrar x -o+ -inul $archive $dir/`)
    elseif fallback == :unzip && Sys.which("unzip") !== nothing
        Base.run(`unzip -q -o $archive $patterns -d $dir`)
    else
        error(L("Zum Entpacken wird bsdtar (Paket libarchive-tools) oder {1} benötigt.", fallback))
    end
    return dir
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
        if !isdir(joinpath(src, "Snare"))
            rar = fetch_file(CROCELL_URL, joinpath(cache, "CrocellKit_Stereo_MIX.rar"), "CrocellKit"; log)
            log(L("{1} wird entpackt …", "CrocellKit"))
            extract(rar, cache; fallback = :unrar)
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
        if !isdir(joinpath(src, "Samples", "oh"))
            zip = fetch_file(VIRTUOSITY_URL, joinpath(cache, basename(VIRTUOSITY_URL)), "VirtuosityDrums"; log)
            log(L("{1} wird entpackt …", "VirtuosityDrums"))
            extract(zip, src, ["Samples/$m/*" for m in VIRTUOSITY_MICS]; fallback = :unzip)
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
# Automatic download on first start
# ---------------------------------------------------------------------------

"Kits that can be downloaded and built: (name, size label, build function)."
const DOWNLOADABLE_KITS = [("CrocellKit", "561 MB", build_crocell), ("VirtuosityDrums", "1,2 GB", build_virtuosity)]

"Downloadable kits that are not installed yet."
missing_kits() = [k for k in DOWNLOADABLE_KITS if !any(e -> e.name == k[1], kit_entries())]

"""
Automatic download is on unless the setting `auto_kits = false` is stored or the environment
variable `DRUMMACHINE_NO_KIT_DOWNLOAD` is set.
"""
auto_kits_enabled() = !haskey(ENV, "DRUMMACHINE_NO_KIT_DOWNLOAD") && get(load_settings(), "auto_kits", true) != false

"""
    auto_fetch_kits!(post, done) -> Union{Task,Nothing}

Builds all missing downloadable kits one after another on a background thread. `post(msg)` gets
progress and error messages, `done(name)` is called after each finished kit. Returns `nothing`
if there is nothing to do or the automatic download is switched off.
"""
function auto_fetch_kits!(post::Function, done::Function)
    (auto_kits_enabled() && !isempty(missing_kits())) || return nothing
    return Threads.@spawn begin
        for (name, size, build) in missing_kits()
            post(L("Erster Start: Kit {1} wird geladen ({2}, läuft im Hintergrund) …", name, size))
            try
                build(; log = post)
                done(name)
            catch e
                post(L("Kit {1} konnte nicht geladen werden: {2}", name, sprint(showerror, e)))
                @warn L("Kit {1} konnte nicht geladen werden", name) exception = e
            end
        end
    end
end
