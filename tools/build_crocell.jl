# Builds the kit "CrocellKit" from the stereo mix of the DrumGizmo CrocellKit (CC BY 4.0).
#
#   julia --project=. tools/build_crocell.jl                 # downloads (561 MB) and builds
#   julia --project=. tools/build_crocell.jl /path/CrocellKit_Stereo_MIX   # already extracted
#
# Result: kits/CrocellKit/ (~70 MB, not in git). Extracting the RAR archive requires
# `bsdtar` (libarchive) or `unrar`. Selection/calibration: see tools/kitbuilder.jl.

include("kitbuilder.jl")
import Downloads

const URL = "https://drumgizmo.org/kits/CrocellKit/CrocellKit_Stereo_MIX.rar"
const DEST = joinpath(@__DIR__, "..", "kits", "CrocellKit")

# track => instrument folder(s) in the mix
const MAP = [
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

function fetch_mix()
    cache = joinpath(homedir(), ".cache", "DrumMachine")
    dir = joinpath(cache, "CrocellKit_Stereo_MIX")
    isdir(joinpath(dir, "Snare")) && return dir
    mkpath(cache)
    rar = joinpath(cache, "CrocellKit_Stereo_MIX.rar")
    if !isfile(rar)
        println("Lade $URL (561 MB) …")
        Downloads.download(URL, rar)
    end
    println("Entpacke …")
    if Sys.which("bsdtar") !== nothing
        run(`bsdtar -xf $rar -C $cache`)
    elseif Sys.which("unrar") !== nothing
        run(`unrar x -o+ $rar $cache/`)
    else
        error("Zum Entpacken wird bsdtar (libarchive-tools) oder unrar benötigt.")
    end
    return dir
end

function main(src)
    loader(f) = () -> WAV.wavread(f; format = "double")[1:2]
    sources = map(MAP) do (id, insts)
        files = [joinpath(src, i, "samples", f) for i in insts for f in readdir(joinpath(src, i, "samples"))
                 if endswith(lowercase(f), ".wav")]
        id => [loader(f) for f in files]
    end
    build_kit(DEST, "CrocellKit", sources;
        header = "# Erzeugt von tools/build_crocell.jl – CrocellKit (DrumGizmo), Stereo-Mix von Henry Järvinen",
        license = """
        CrocellKit (DrumGizmo) – Stereo-Mix
        Kit: Crocell (crocell.dk), Aufbau Andreas; Mikrofonierung Jacob Olsen (JBOSound);
        gesampelt und für DrumGizmo aufbereitet von Lars Muldjord / DrumGizmo-Team (drumgizmo.org).
        Stereo-Mix: Henry Järvinen.
        Quelle: $URL
        Lizenz: Creative Commons Attribution 4.0 International (CC BY 4.0)
                https://creativecommons.org/licenses/by/4.0/

        Änderungen durch tools/build_crocell.jl (DrumMachine.jl): Auswahl einzelner Aufnahmen,
        Resampling 48 → 44,1 kHz, Kürzen/Ausblenden, Umwandlung in 16 Bit, Pegelangleich.
        """)
end

main(isempty(ARGS) ? fetch_mix() : ARGS[1])
