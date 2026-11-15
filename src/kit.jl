# Instruments, kits (WAV samples with velocity layers) and a synthetic fallback kit.

using Random: MersenneTwister
import WAV
import TOML

"Tracks in fixed order: (id, display name)."
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

track_index(id::AbstractString) = findfirst(==(id), TRACK_IDS)

"One recording: left and right channel (for mono, `r === l`)."
struct Sample
    l::Vector{Float32}
    r::Vector{Float32}
end
Sample(x::Vector{Float32}) = Sample(x, x)
isstereo(s::Sample) = s.l !== s.r
Base.length(s::Sample) = length(s.l)

"""
A kit: any number of velocity layers per track (soft -> loud), one or more recordings per
layer (round-robin). Plus pan, gain and choke group per track.
"""
struct Kit
    name::String
    layers::Vector{Vector{Vector{Sample}}}   # [track][layer][round-robin]
    pan::Vector{Float32}
    gain::Vector{Float32}
    choke::Vector{Int}
    level_gain::NTuple{3,Float32}            # extra gain for ghost note/normal/accent
end
"Default extra gain: dynamics via level, for kits with few layers."
const DEFAULT_LEVEL_GAIN = (0.5f0, 0.8f0, 1.0f0)
Kit(name, layers, pan, gain, choke) = Kit(name, layers, pan, gain, choke, DEFAULT_LEVEL_GAIN)

# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------

_t(n) = (0:n-1) ./ SR
_n(sec) = round(Int, sec * SR)

function _metal(n, base; rng)
    # six square-wave oscillators at inharmonic frequencies (classic cymbal synthesis)
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

"Synthetic kit: one layer per track (dynamics via level only)."
function synth_kit()
    layers = [[[Sample(synth_sound(id))]] for id in TRACK_IDS]
    pan = Float32[0, -0.2, -0.2, -0.35, -0.35, -0.35, -0.1, 0.4, 0.35, 0.35, -0.4]
    gain = Float32[1.0, 0.8, 0.7, 0.45, 0.45, 0.4, 0.8, 0.8, 0.35, 0.4, 0.4]
    choke = [0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0]
    return Kit("Synth", layers, pan, gain, choke)
end

"Click for count-in/metronome (high = downbeat of the bar)."
function click_sound(hi::Bool)
    n = _n(0.05); t = _t(n)
    f = hi ? 1800.0 : 1200.0
    return Sample(finish(sin.(2π * f .* t) .* exp.(-t ./ 0.008); peak = 0.8))
end

# ---------------------------------------------------------------------------
# WAV kits
# ---------------------------------------------------------------------------

"Resample to `SR` (sinc, see `resample_sinc`)."
resample(x::AbstractVector, fs::Real) = resample_sinc(x, fs, SR)

"Load a WAV file as a `Sample` (mono or stereo; more channels are mixed down to stereo)."
function load_sample(path; stereo::Bool = true)
    y, fs = WAV.wavread(path; format = "double")
    nch = size(y, 2)
    if nch == 1 || !stereo
        return trim_onset(Sample(resample(vec(sum(y; dims = 2)) ./ nch, fs)))
    end
    l = resample(view(y, :, 1), fs)
    r = resample(view(y, :, 2), fs)
    return trim_onset(Sample(l, r))
end

load_wav_mono(path) = load_sample(path; stereo = false)

"""
Align a sample's attack with the grid point: cut everything up to `pre` seconds before the
level first exceeds `thresh` x peak, and fade in the remainder smoothly.
Important e.g. for the hi-hat pedal, which has ~15 ms of quiet pre-noise before the "chick".
"""
function trim_onset(s::Sample; thresh = 0.1, pre = 0.001)
    env = isstereo(s) ? max.(abs.(s.l), abs.(s.r)) : abs.(s.l)
    pk = maximum(env; init = 0f0)
    pk == 0 && return s
    i = findfirst(>(thresh * pk), env)
    np = round(Int, pre * SR)
    k = i - np
    k <= 1 && return s
    cut(x) = (y = x[k:end]; for j in 1:np; y[j] *= Float32((j - 1) / np); end; y)
    return isstereo(s) ? Sample(cut(s.l), cut(s.r)) : Sample(cut(s.l))
end

"""
    load_kit(dir) -> Kit

Load a kit from `dir/kit.toml`. Each track supports two formats:

- `file = "36-Pearl-22-Kick"`: files `<file>-1.wav` ... `<file>-N.wav` (soft -> loud),
  or a single `<file>.wav` (see `kits/BlackPearl/kit.toml`).
- `folder = "Kick"`: folder with `<layer>-<rr>.wav`, e.g. `01-1.wav`, `01-2.wav`, `02-1.wav` ...
  (layers soft -> loud, several round-robins per layer).

Missing tracks are filled with synthetic sounds.
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
        ls = haskey(t, "folder") ? load_folder_layers(joinpath(dir, t["folder"])) :
                                    load_prefix_layers(dir, t["file"])
        if isempty(ls)
            @warn "Kit $name: keine Samples für $id gefunden, nutze Synth-Klang" t
        else
            layers[k] = ls
        end
        pan[k] = get(t, "pan", pan[k])
        gain[k] = get(t, "gain", 1.0)
        choke[k] = get(t, "choke", 0)
    end
    lg = get(cfg, "level_gain", collect(DEFAULT_LEVEL_GAIN))
    return Kit(name, layers, pan, gain, choke, Tuple(Float32.(lg)))
end

function load_prefix_layers(dir, prefix)
    ls = Vector{Sample}[]
    l = 1
    while isfile(joinpath(dir, "$prefix-$l.wav"))
        push!(ls, [load_sample(joinpath(dir, "$prefix-$l.wav"))])
        l += 1
    end
    if isempty(ls) && isfile(joinpath(dir, "$prefix.wav"))
        push!(ls, [load_sample(joinpath(dir, "$prefix.wav"))])
    end
    return ls
end

function load_folder_layers(folder)
    isdir(folder) || return Vector{Sample}[]
    byl = Dict{Int,Vector{Sample}}()
    for f in sort(readdir(folder))
        m = match(r"^(\d+)-(\d+)\.wav$"i, f)
        m === nothing && continue
        push!(get!(byl, parse(Int, m[1]), Sample[]), load_sample(joinpath(folder, f)))
    end
    return [byl[l] for l in sort(collect(keys(byl)))]
end

const KIT_DIR = normpath(joinpath(@__DIR__, "..", "kits"))

"""
All kits: WAV kits from `kits/` (alphabetical), followed by the 808- and 909-style synth kits.
The basic synth kit only serves as a fallback for missing samples.
"""
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
    push!(kits, kit_808(), kit_909())
    return kits
end
