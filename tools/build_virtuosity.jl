# Baut das Kit "VirtuosityDrums" (Jazz-Kit von Versilian Studios / Karoryfer, CC0).
#
#   julia --project=. tools/build_virtuosity.jl           # lädt herunter (1,2 GB) und baut
#   julia --project=. tools/build_virtuosity.jl /pfad/zum/entpackten/Ordner
#
# Ergebnis: kits/VirtuosityDrums/ (nicht im Git). Entpacken mit `bsdtar` oder `unzip`;
# FLAC wird mit dem `flac` aus FLAC_jll dekodiert (keine Systempakete nötig).
#
# Mix wie im Hersteller-Preset „Basic Kit“: Overheads (Stereo) + Kick-Mikro + Snare-Mikro,
# alle gleich laut; das Übersprechen der Nahmikrofone gehört zum Klang.

include("kitbuilder.jl")
import Downloads
using FLAC_jll: flac

const URL = "https://github.com/sfzinstruments/virtuosity_drums/releases/download/v0.925/Virtuosity_Drums_v0.925.zip"
const DEST = joinpath(@__DIR__, "..", "kits", "VirtuosityDrums")
const MICS = ("oh", "kickmic", "snaremic")

# Spur => (Instrument-Ordner, Artikulation)  →  <mic>/<inst>/<mic>_<inst>_<art>_vl<N>[_rr<M>].flac
const MAP = [
    "Kick"     => ("kick", "snon"),          # Kick mit eingeschaltetem Snare-Teppich
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

function fetch()
    cache = joinpath(homedir(), ".cache", "DrumMachine")
    dir = joinpath(cache, "VirtuosityDrums")
    isdir(joinpath(dir, "Samples", "oh")) && return dir
    mkpath(cache)
    zip = joinpath(cache, basename(URL))
    if !isfile(zip)
        println("Lade $URL (1,2 GB) …")
        Downloads.download(URL, zip)
    end
    println("Entpacke (nur benötigte Mikrofone) …")
    mkpath(dir)
    pats = ["Samples/$m/*" for m in MICS]
    if Sys.which("bsdtar") !== nothing
        run(`bsdtar -xf $zip -C $dir $pats`)
    elseif Sys.which("unzip") !== nothing
        run(`unzip -q -o $zip $pats -d $dir`)
    else
        error("Zum Entpacken wird bsdtar (libarchive-tools) oder unzip benötigt.")
    end
    return dir
end

"Sucht den Ordner `Samples` unterhalb von `root`."
function samples_dir(root)
    for (d, dirs, _) in walkdir(root)
        "Samples" in dirs && isdir(joinpath(d, "Samples", "oh")) && return joinpath(d, "Samples")
    end
    error("Kein Samples/oh unter $root gefunden")
end

function read_flac(path)
    tmp = tempname() * ".wav"
    try
        run(`$(flac()) -d -s -f -o $tmp $path`)
        y, fs = WAV.wavread(tmp; format = "double")
        return y, fs
    finally
        rm(tmp; force = true)
    end
end

"Mischt alle vorhandenen Mikrofone einer Aufnahme zu Stereo (Mono-Mikros in die Mitte)."
function mix_mics(sdir, inst, stem)
    parts = Matrix{Float64}[]
    fs = 0.0
    for m in MICS
        f = joinpath(sdir, m, inst, "$(m)_$stem.flac")
        isfile(f) || continue
        y, fs = read_flac(f)
        push!(parts, size(y, 2) == 1 ? hcat(y, y) .* 0.7071 : y[:, 1:2])
    end
    isempty(parts) && error("Keine Aufnahme für $stem")
    n = maximum(size.(parts, 1))
    out = zeros(n, 2)
    for p in parts
        out[1:size(p, 1), :] .+= p
    end
    return out, fs
end

function main(root)
    sdir = samples_dir(root)
    sources = map(MAP) do (id, (inst, art))
        prefix = "$(inst)_$(art)_vl"
        stems = sort(unique(replace(f, r"^oh_" => "", r"\.flac$" => "")
                            for f in readdir(joinpath(sdir, "oh", inst)) if startswith(f, "oh_$prefix")))
        isempty(stems) && error("Keine Dateien für $inst/$art")
        id => [() -> mix_mics(sdir, inst, s) for s in stems]
    end
    build_kit(DEST, "VirtuosityDrums", sources;
        header = "# Erzeugt von tools/build_virtuosity.jl – Virtuosity Drums (Versilian Studios / Karoryfer), CC0",
        license = """
        Virtuosity Drums – Contemporary Jazz Drum Kit
        Aufgenommen bei Virtuosity Musical Instruments, Boston (MA); Schlagzeuger: Austin McMahon.
        Erstellt von Versilian Studios LLC und Karoryfer Samples.
        Quelle: https://github.com/sfzinstruments/virtuosity_drums (Release v0.925)
        Lizenz: CC0 1.0 (gemeinfrei) – Nennung erbeten, nicht erforderlich.
                https://creativecommons.org/publicdomain/zero/1.0/

        Änderungen durch tools/build_virtuosity.jl (DrumMachine.jl): Mix aus Overhead-, Kick- und
        Snare-Mikrofon (wie Preset „Basic Kit“), Auswahl einzelner Aufnahmen, Resampling auf
        44,1 kHz, Kürzen/Ausblenden, Umwandlung in 16 Bit, Pegelangleich.
        """)
end

main(isempty(ARGS) ? fetch() : ARGS[1])
