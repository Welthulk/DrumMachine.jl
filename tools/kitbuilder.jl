# Gemeinsame Bausteine der Kit-Build-Skripte (tools/build_*.jl):
# Velocity-Stufen nach gemessenem Pegel auswählen, auf 44,1 kHz resampeln, kürzen,
# als 16-Bit-WAV schreiben und die Balance relativ zur Snare kalibrieren.

using DrumMachine
using DrumMachine: SR, resample_sinc
import WAV

# Velocity-Stufen: Grenzen in dB relativ zum lautesten Schlag des Instruments.
# Ghost = Stufen 1–2, normal = 3–4, Akzent = 5 (siehe `DrumMachine.level_layers`).
const BIN_EDGES = [-32.0, -24.0, -17.0, -11.0, -5.0, 0.01]
const MAX_RR = 4

# Maximale Länge je Spur in Sekunden (Ausklingen wird danach ausgeblendet)
const MAXLEN = Dict("Kick" => 1.2, "Snare" => 1.2, "Rim" => 0.6, "HiHat" => 0.6, "HHOpen" => 2.5,
                    "HHPedal" => 0.6, "Tom" => 2.5, "FloorTom" => 3.0, "Ride" => 5.0,
                    "RideBell" => 4.0, "Crash" => 5.0)

# Balance: Pegel eines „normalen“ Schlags (Stufen 3–4) relativ zur Snare in dB.
const BALANCE_DB = Dict("Kick" => 0.0, "Snare" => 0.0, "Rim" => -6.0, "HiHat" => -8.0,
                        "HHOpen" => -6.0, "HHPedal" => -12.0, "Tom" => -2.0, "FloorTom" => -2.0,
                        "Ride" => -6.0, "RideBell" => -6.0, "Crash" => -4.0)
const SNARE_NORMAL_PEAK = 0.3      # Zielpegel eines normalen Snare-Schlags

"Anschlagspegel: Spitzenwert der ersten 30 ms (alle Kanäle)."
attack_peak(y, fs) = maximum(abs, view(y, 1:min(size(y, 1), round(Int, 0.03fs)), :))

"Stereo-Matrix → 44,1 kHz, auf `maxlen` kürzen, letzte 30 % weich ausblenden."
function process(y::AbstractMatrix, fs, maxlen)
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
    build_kit(dest, name, sources; header, license, choke = ("HiHat", "HHOpen", "HHPedal"))

`sources`: Vektor `spur_id => loaders`, jeder Loader ist eine Funktion `() -> (y::Matrix, fs)`
(eine Aufnahme, Stereo oder Mono). Schreibt `dest/<spur>/<stufe>-<rr>.wav`, `kit.toml`, `LICENSE.txt`.
"""
function build_kit(dest, name, sources; header::AbstractString, license::AbstractString,
                   choke = ("HiHat", "HHOpen", "HHPedal"))
    isdir(dest) && rm(dest; recursive = true)
    mkpath(dest)
    refs = Dict{String,Float64}()
    for (id, loaders) in sources
        print("  $(rpad(id, 9)) ")
        peaks = [attack_peak(ld()...) for ld in loaders]
        db = 20 .* log10.(peaks ./ maximum(peaks))
        mkpath(joinpath(dest, id))
        nfiles = 0
        normal = Float64[]
        for b in 1:length(BIN_EDGES)-1
            lo, hi = BIN_EDGES[b], BIN_EDGES[b+1]
            idx = [i for i in eachindex(db) if lo <= db[i] < hi]
            isempty(idx) && (idx = sortperm(abs.(db .- (lo + hi) / 2))[1:1])   # leere Stufe: nächste Aufnahme
            idx = sort(idx; by = i -> db[i])
            pick = length(idx) <= MAX_RR ? idx : idx[round.(Int, range(1, length(idx), length = MAX_RR))]
            for (rr, i) in enumerate(unique(pick))
                y, fs = loaders[i]()
                out = process(y, fs, MAXLEN[id])
                pcm = round.(Int16, clamp.(out, -1, 1) .* 32767)
                WAV.wavwrite(pcm, joinpath(dest, id, "$b-$rr.wav"); Fs = SR, nbits = 16,
                             compression = WAV.WAVE_FORMAT_PCM)
                nfiles += 1
                b in (3, 4) && push!(normal, attack_peak(out, SR))
            end
        end
        refs[id] = sort(normal)[cld(length(normal), 2)]
        println("$(length(loaders)) Aufnahmen → $nfiles ausgewählt")
    end
    io = IOBuffer()
    println(io, header)
    println(io, "name = \"$name\"")
    println(io, "# Die Samples tragen ihre Dynamik selbst, daher kaum zusätzlicher Pegelunterschied")
    println(io, "level_gain = [0.9, 1.0, 1.0]\n")
    println(io, "[tracks]")
    for (id, _) in sources
        g = SNARE_NORMAL_PEAK / refs[id] * 10^(BALANCE_DB[id] / 20)
        ch = id in choke ? ", choke = 1" : ""
        println(io, rpad("$id ", 10), "= { folder = \"$id\", pan = 0.0, gain = $(round(g, digits = 2))$ch }")
    end
    write(joinpath(dest, "kit.toml"), String(take!(io)))
    write(joinpath(dest, "LICENSE.txt"), license)
    println("Fertig: $(normpath(dest))")
end
