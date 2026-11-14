# Baut das Kit "CrocellKit" aus dem Stereo-Mix des DrumGizmo-CrocellKit.
#
#   julia --project=. tools/build_crocell.jl                 # lädt herunter (561 MB) und baut
#   julia --project=. tools/build_crocell.jl /pfad/CrocellKit_Stereo_MIX   # schon entpackt
#
# Ergebnis: kits/CrocellKit/ (~70 MB, nicht im Git). Zum Entpacken des RAR-Archivs wird
# `bsdtar` (libarchive) oder `unrar` benötigt.
#
# Was das Skript tut:
#   - pro Spur 5 Velocity-Stufen nach gemessenem Anschlagspegel (-32 … 0 dB) mit bis zu
#     4 Round-Robin-Aufnahmen je Stufe auswählen
#   - 48 kHz → 44,1 kHz (Sinc), Ausklingen auf sinnvolle Längen kürzen und ausblenden
#   - die Lautstärke-Balance des Original-Mixes beibehalten

using DrumMachine
using DrumMachine: SR, resample_sinc
import WAV
import Downloads

const URL = "https://drumgizmo.org/kits/CrocellKit/CrocellKit_Stereo_MIX.rar"
const DEST = joinpath(@__DIR__, "..", "kits", "CrocellKit")

# Spur => (Instrument-Ordner im Mix, maximale Länge in s)
const MAP = [
    "Kick"     => (["KDrumR", "KDrumL"], 1.2),   # beide Beater der Doppelfußmaschine als Round-Robin
    "Snare"    => (["Snare"], 1.2),
    "Rim"      => (["SnareRim"], 0.6),
    "HiHat"    => (["HihatClosed"], 0.6),
    "HHOpen"   => (["HihatOpen"], 2.5),
    "HHPedal"  => (["HihatPedal"], 0.6),
    "Tom"      => (["Tom1"], 2.5),
    "FloorTom" => (["FTom1"], 3.0),
    "Ride"     => (["RideR"], 5.0),
    "RideBell" => (["RideRBell"], 4.0),
    "Crash"    => (["CrashL"], 5.0),
]

# Velocity-Stufen: Mitten in dB relativ zum lautesten Schlag des Instruments.
# Ghost = Stufen 1–2, normal = 3–4, Akzent = 5 (siehe `level_layers`).
const BIN_EDGES = [-32.0, -24.0, -17.0, -11.0, -5.0, 0.01]
const MAX_RR = 4

# Balance: Pegel eines „normalen“ Schlags (Stufen 3–4) relativ zur Snare in dB. Der Original-Mix
# (Metal) hat sehr leise Becken; zum Üben sollen Hihat und Ride klar hörbar sein.
const BALANCE_DB = Dict("Kick" => 0.0, "Snare" => 0.0, "Rim" => -6.0, "HiHat" => -8.0,
                        "HHOpen" => -6.0, "HHPedal" => -12.0, "Tom" => -2.0, "FloorTom" => -2.0,
                        "Ride" => -6.0, "RideBell" => -6.0, "Crash" => -4.0)
const SNARE_NORMAL_PEAK = 0.3      # Zielpegel eines normalen Snare-Schlags

function fetch_mix()
    cache = joinpath(homedir(), ".cache", "DrumMachine")
    dir = joinpath(cache, "CrocellKit_Stereo_MIX")
    isdir(dir) && return dir
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

"Anschlagspegel: Spitzenwert der ersten 30 ms (beide Kanäle)."
attack_peak(y, fs) = maximum(abs, view(y, 1:min(size(y, 1), round(Int, 0.03fs)), :))

function process(y::Matrix, fs, maxlen)
    l = resample_sinc(view(y, :, 1), fs, SR)
    r = resample_sinc(view(y, :, size(y, 2) > 1 ? 2 : 1), fs, SR)
    n = min(length(l), round(Int, maxlen * SR))
    l = l[1:n]; r = r[1:n]
    nf = round(Int, 0.3n)                  # letzte 30 % weich ausblenden (Kosinus)
    for k in 1:nf
        g = Float32(0.5 + 0.5cospi(k / nf))
        l[n-nf+k] *= g; r[n-nf+k] *= g
    end
    return hcat(l, r)
end

function build(src::AbstractString)
    isdir(DEST) && rm(DEST; recursive = true)
    mkpath(DEST)
    toml = IOBuffer()
    println(toml, "# Erzeugt von tools/build_crocell.jl – CrocellKit (DrumGizmo), Stereo-Mix von Henry Järvinen")
    println(toml, "name = \"CrocellKit\"")
    println(toml, "# Die Samples tragen ihre Dynamik selbst, daher kein zusätzlicher Pegelunterschied")
    println(toml, "level_gain = [0.9, 1.0, 1.0]\n")
    println(toml, "[tracks]")
    refs = Dict{String,Float64}()
    lines = String[]
    for (id, (insts, maxlen)) in MAP
        files = [joinpath(src, i, "samples", f) for i in insts for f in readdir(joinpath(src, i, "samples"))
                 if endswith(lowercase(f), ".wav")]
        peaks = map(files) do f
            y, fs = WAV.wavread(f; format = "double")
            attack_peak(y, fs)
        end
        db = 20 .* log10.(peaks ./ maximum(peaks))
        used = Set{Int}()  # (nur zur Übersicht)
        mkpath(joinpath(DEST, id))
        nfiles = 0
        normal = Float64[]
        for b in 1:length(BIN_EDGES)-1
            lo, hi = BIN_EDGES[b], BIN_EDGES[b+1]
            idx = [i for i in eachindex(db) if lo <= db[i] < hi]
            if isempty(idx)                # leere Stufe: nächstgelegene Aufnahmen nehmen
                c = (lo + hi) / 2
                idx = sortperm(abs.(db .- c))[1:1]
            end
            # gleichmäßig über die Stufe verteilt auswählen
            idx = sort(idx; by = i -> db[i])
            pick = length(idx) <= MAX_RR ? idx : idx[round.(Int, range(1, length(idx), length = MAX_RR))]
            for (rr, i) in enumerate(unique(pick))
                y, fs = WAV.wavread(files[i]; format = "double")
                out = process(y, fs, maxlen)
                pcm = round.(Int16, clamp.(out, -1, 1) .* 32767)
                WAV.wavwrite(pcm, joinpath(DEST, id, "$b-$rr.wav"); Fs = SR, nbits = 16,
                             compression = WAV.WAVE_FORMAT_PCM)
                push!(used, i); nfiles += 1
                b in (3, 4) && push!(normal, attack_peak(out, SR))
            end
        end
        refs[id] = sort(normal)[cld(length(normal), 2)]     # Median
        println("  $(rpad(id, 9)) $(length(files)) Aufnahmen → $nfiles ausgewählt")
    end
    for (id, _) in MAP
        g = SNARE_NORMAL_PEAK / refs[id] * 10^(BALANCE_DB[id] / 20)
        choke = id in ("HiHat", "HHOpen", "HHPedal") ? ", choke = 1" : ""
        println(toml, rpad("$id ", 10), "= { folder = \"$id\", pan = 0.0, gain = $(round(g, digits = 2))$choke }")
    end
    write(joinpath(DEST, "kit.toml"), String(take!(toml)))
    write(joinpath(DEST, "LICENSE.txt"), """
    CrocellKit (DrumGizmo) – Stereo-Mix
    Kit: Crocell (crocell.dk), Aufbau Andreas; Mikrofonierung Jacob Olsen (JBOSound);
    gesampelt und für DrumGizmo aufbereitet von Lars Muldjord / DrumGizmo-Team (drumgizmo.org).
    Stereo-Mix: Henry Järvinen.
    Quelle: $URL
    Lizenz: Creative Commons Attribution 4.0 International (CC BY 4.0)
            https://creativecommons.org/licenses/by/4.0/

    Änderungen durch tools/build_crocell.jl (DrumMachine.jl): Auswahl einzelner Aufnahmen,
    Resampling 48 → 44,1 kHz, Kürzen/Ausblenden, Umwandlung in 16 Bit.
    """)
    println("Fertig: $(normpath(DEST))")
end

build(isempty(ARGS) ? fetch_mix() : ARGS[1])
