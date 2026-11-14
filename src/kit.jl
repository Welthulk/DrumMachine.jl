# Instrumente, Kits (WAV-Samples mit Velocity-Layern) und ein synthetisches Ersatz-Kit.

using Random: MersenneTwister
import WAV
import TOML

"Spuren in fester Reihenfolge: (id, Anzeigename)."
const TRACKS = [
    ("Kick",     "Kick"),
    ("Snare",    "Snare"),
    ("Rim",      "Side Stick"),
    ("HiHat",    "HiHat"),
    ("HHOpen",   "HH offen"),
    ("HHPedal",  "HH Pedal"),
    ("Tom",      "Tom"),
    ("FloorTom", "Floor Tom"),
    ("Ride",     "Ride"),
    ("RideBell", "Ride Bell"),
    ("Crash",    "Crash"),
]
const NTRACKS = length(TRACKS)
const TRACK_IDS = first.(TRACKS)
const NLAYERS = 5

track_index(id::AbstractString) = findfirst(==(id), TRACK_IDS)

"""
Ein Kit: pro Spur `NLAYERS` Samples (leise → laut), dazu Panorama, Pegel und Choke-Gruppe.
"""
struct Kit
    name::String
    layers::Vector{Vector{Vector{Float32}}}   # [spur][layer] -> Samples (mono)
    pan::Vector{Float32}
    gain::Vector{Float32}
    choke::Vector{Int}
end

# ---------------------------------------------------------------------------
# Synthese
# ---------------------------------------------------------------------------

_t(n) = (0:n-1) ./ SR
_n(sec) = round(Int, sec * SR)

function _metal(n, base; rng)
    # sechs Rechteck-Oszillatoren mit inharmonischen Frequenzen (klassische Becken-Synthese)
    freqs = (205.3, 304.4, 369.6, 522.7, 540.0, 800.0) .* base
    t = _t(n)
    x = zeros(n)
    for f in freqs
        ph = rand(rng)
        x .+= sign.(sin.(2π .* (f .* t .+ ph)))
    end
    return x
end

function synth_sound(id::AbstractString)
    rng = MersenneTwister(hash(id))
    noise(n) = 2 .* rand(rng, n) .- 1
    if id == "Kick"
        n = _n(0.6); t = _t(n)
        f = 48 .+ 110 .* exp.(-t ./ 0.035)
        ph = cumsum(2π .* f ./ SR)
        click = highpass!(noise(n), 2000) .* exp.(-t ./ 0.003)
        return finish(sin.(ph) .* exp.(-t ./ 0.28) .+ 0.25 .* click)
    elseif id == "Snare"
        n = _n(0.45); t = _t(n)
        tone = (sin.(2π * 185 .* t) .+ 0.5 .* sin.(2π * 330 .* t)) .* exp.(-t ./ 0.06)
        nz = highpass!(noise(n), 1200) .* exp.(-t ./ 0.14)
        return finish(0.6 .* tone .+ nz)
    elseif id == "Rim"
        n = _n(0.12); t = _t(n)
        tone = sin.(2π * 520 .* t) .* exp.(-t ./ 0.02)
        nz = bandpass!(noise(n), 2500, 2.0) .* exp.(-t ./ 0.008)
        return finish(tone .+ 3 .* nz)
    elseif id in ("HiHat", "HHOpen", "HHPedal")
        dec = id == "HiHat" ? 0.045 : id == "HHOpen" ? 0.35 : 0.03
        n = _n(dec * 7); t = _t(n)
        x = _metal(n, 1.0; rng) .+ 0.5 .* noise(n)
        bandpass!(x, id == "HHPedal" ? 6000 : 9000, 0.9)
        highpass!(x, 5000)
        return finish(x .* exp.(-t ./ dec))
    elseif id in ("Tom", "FloorTom")
        f0 = id == "Tom" ? 190.0 : 105.0
        n = _n(0.9); t = _t(n)
        f = f0 .* (1 .+ 0.35 .* exp.(-t ./ 0.05))
        ph = cumsum(2π .* f ./ SR)
        nz = lowpass!(noise(n), 3000) .* exp.(-t ./ 0.01)
        return finish(sin.(ph) .* exp.(-t ./ 0.35) .+ 0.2 .* nz)
    elseif id == "Ride"
        n = _n(2.5); t = _t(n)
        x = _metal(n, 1.7; rng)
        bandpass!(x, 5000, 0.6)
        ping = highpass!(noise(n), 6000) .* exp.(-t ./ 0.01)
        return finish(x .* exp.(-t ./ 0.9) .+ 0.6 .* ping)
    elseif id == "RideBell"
        n = _n(2.0); t = _t(n)
        x = sum(a .* sin.(2π * f .* t) for (f, a) in ((610, 1.0), (1410, 0.6), (2330, 0.4), (3170, 0.25)))
        return finish(x .* exp.(-t ./ 0.7))
    elseif id == "Crash"
        n = _n(3.0); t = _t(n)
        x = 0.4 .* _metal(n, 2.1; rng) .+ noise(n)
        highpass!(x, 3500)
        att = min.(1.0, t ./ 0.002)
        return finish(x .* att .* exp.(-t ./ 0.9))
    end
    error("Unbekanntes Instrument $id")
end

"Synthetisches Kit: alle Layer teilen sich dasselbe Sample (Dynamik nur über Pegel)."
function synth_kit()
    layers = [fill(synth_sound(id), NLAYERS) for id in TRACK_IDS]
    pan = Float32[0, -0.2, -0.2, -0.35, -0.35, -0.35, -0.1, 0.4, 0.35, 0.35, -0.4]
    gain = Float32[1.0, 0.8, 0.7, 0.45, 0.45, 0.4, 0.8, 0.8, 0.35, 0.4, 0.4]
    choke = [0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0]
    return Kit("Synth", layers, pan, gain, choke)
end

"Klick für Einzähler/Metronom (hoch = Takt-Eins)."
function click_sound(hi::Bool)
    n = _n(0.05); t = _t(n)
    f = hi ? 1800.0 : 1200.0
    return finish(sin.(2π * f .* t) .* exp.(-t ./ 0.008); peak = 0.8)
end

# ---------------------------------------------------------------------------
# WAV-Kits
# ---------------------------------------------------------------------------

function load_wav_mono(path)
    y, fs = WAV.wavread(path; format = "double")
    x = size(y, 2) > 1 ? vec(sum(y; dims = 2)) ./ size(y, 2) : vec(y)
    if round(Int, fs) != SR                 # lineares Resampling
        r = fs / SR
        m = floor(Int, (length(x) - 1) / r)
        x = [let p = 1 + (k - 1) * r, i = floor(Int, p), fr = p - i
                 x[i] * (1 - fr) + x[min(i + 1, end)] * fr
             end for k in 1:m]
    end
    return trim_onset(Float32.(x))
end

"""
Legt den Anschlag eines Samples auf den Rasterpunkt: schneidet alles bis `pre` Sekunden vor
dem ersten Überschreiten von `thresh` × Spitzenpegel ab und blendet diesen Rest weich ein.
Wichtig z. B. beim Hi-Hat-Pedal, das ~15 ms leises Vorgeräusch hat, bevor das „Chick“ kommt.
"""
function trim_onset(x::Vector{Float32}; thresh = 0.1, pre = 0.001)
    pk = maximum(abs, x; init = 0f0)
    pk == 0 && return x
    i = findfirst(v -> abs(v) > thresh * pk, x)
    np = round(Int, pre * SR)
    k = i - np
    k <= 1 && return x
    y = x[k:end]
    for j in 1:np
        y[j] *= Float32((j - 1) / np)
    end
    return y
end

"""
    load_kit(dir) -> Kit

Lädt ein Kit aus `dir/kit.toml` (siehe `kits/BlackPearl/kit.toml`). Fehlende Spuren
oder Layer werden mit synthetischen Klängen bzw. dem nächstgelegenen Layer aufgefüllt.
"""
function load_kit(dir::AbstractString; fallback::Kit = synth_kit())
    cfg = TOML.parsefile(joinpath(dir, "kit.toml"))
    name = get(cfg, "name", basename(dir))
    tr = get(cfg, "tracks", Dict{String,Any}())
    layers = deepcopy(fallback.layers)
    pan = copy(fallback.pan); gain = copy(fallback.gain); choke = copy(fallback.choke)
    for (k, id) in enumerate(TRACK_IDS)
        haskey(tr, id) || continue
        t = tr[id]
        prefix = t["file"]
        found = [isfile(joinpath(dir, "$prefix-$l.wav")) ? load_wav_mono(joinpath(dir, "$prefix-$l.wav")) : nothing
                 for l in 1:NLAYERS]
        if all(isnothing, found) && isfile(joinpath(dir, "$prefix.wav"))
            found = fill(load_wav_mono(joinpath(dir, "$prefix.wav")), NLAYERS)
        end
        if any(!isnothing, found)
            avail = findall(!isnothing, found)
            layers[k] = [found[avail[argmin(abs.(avail .- l))]] for l in 1:NLAYERS]
        else
            @warn "Kit $name: keine Samples für $id gefunden, nutze Synth-Klang" prefix
        end
        pan[k] = get(t, "pan", pan[k])
        gain[k] = get(t, "gain", 1.0)
        choke[k] = get(t, "choke", 0)
    end
    return Kit(name, layers, pan, gain, choke)
end

const KIT_DIR = normpath(joinpath(@__DIR__, "..", "kits"))

"Alle Kits: WAV-Kits aus `kits/` (alphabetisch) und zuletzt das Synth-Kit."
function available_kits(dir = KIT_DIR)
    syn = synth_kit()
    kits = Kit[]
    if isdir(dir)
        for d in sort(readdir(dir; join = true))
            isfile(joinpath(d, "kit.toml")) || continue
            try
                push!(kits, load_kit(d; fallback = syn))
            catch e
                @warn "Kit $(basename(d)) konnte nicht geladen werden" exception = e
            end
        end
    end
    push!(kits, syn)
    return kits
end
