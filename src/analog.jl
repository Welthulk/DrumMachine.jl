# Analog-modelled drum machine kits in the style of the classic TR-808 and TR-909.
# All sounds are synthesized at startup (no samples).

using Random: MersenneTwister

# --- small building blocks --------------------------------------------------

_env(t, τ) = exp.(-t ./ τ)
_sq(f, t, ph = 0.0) = sign.(sin.(2π .* (f .* t .+ ph)))
"Sine with time-varying frequency f(t) (vector), phase-continuous."
_sweep(f) = sin.(cumsum(2π .* f ./ SR))
"Six inharmonic square-wave oscillators (the metal source of the 808/909)."
const METAL_FREQS = (205.3, 304.4, 369.6, 522.7, 540.0, 800.0)
_metal6(t; scale = 1.0) = sum(_sq(f * scale, t, 0.13k) for (k, f) in enumerate(METAL_FREQS))
_noise(rng, n) = 2 .* rand(rng, n) .- 1
"Soft saturation like an overdriven analog stage."
_sat(x, drive) = tanh.(drive .* x) ./ tanh(drive)

# --- 808 style --------------------------------------------------------------

function sound_808(id::AbstractString)
    rng = MersenneTwister(hash((808, id)))
    if id == "Kick"
        # Bridged-T resonator: low sine, slight pitch drop, long decay
        n = _n(1.4); t = _t(n)
        f = 49 .+ 14 .* _env(t, 0.06)
        click = lowpass!(_noise(rng, n), 4000) .* _env(t, 0.002)
        x = _sweep(f) .* _env(t, 0.42) .+ 0.12 .* click
        return finish(_sat(x, 1.6))
    elseif id == "Snare"
        n = _n(0.45); t = _t(n)
        tone = 0.65 .* sin.(2π * 180 .* t) .* _env(t, 0.045) .+ 0.45 .* sin.(2π * 330 .* t) .* _env(t, 0.03)
        snappy = highpass!(lowpass!(_noise(rng, n), 9000), 1800) .* _env(t, 0.11)
        return finish(tone .+ 0.75 .* snappy)
    elseif id == "Rim"
        # Rimshot: two high, very short resonances
        n = _n(0.08); t = _t(n)
        x = (sin.(2π * 1720 .* t) .+ 0.6 .* sin.(2π * 470 .* t)) .* _env(t, 0.009)
        return finish(highpass!(x, 300))
    elseif id in ("HiHat", "HHOpen", "HHPedal")
        dec = id == "HiHat" ? 0.04 : id == "HHOpen" ? 0.32 : 0.022
        n = _n(dec * 8); t = _t(n)
        m = _metal6(t)
        x = bandpass!(copy(m), 3440, 1.2) .+ bandpass!(copy(m), 7100, 1.2)
        highpass!(x, 6500)
        return finish(x .* _env(t, dec); peak = id == "HHPedal" ? 0.6 : 1.0)
    elseif id in ("Tom", "FloorTom")
        f0 = id == "Tom" ? 165.0 : 98.0
        n = _n(0.9); t = _t(n)
        f = f0 .* (1 .+ 0.12 .* _env(t, 0.08))
        nz = lowpass!(_noise(rng, n), 2500) .* _env(t, 0.004)
        return finish(_sweep(f) .* _env(t, 0.22) .+ 0.08 .* nz)
    elseif id == "Ride"
        # 808 has no ride: cymbal circuit, shorter and brighter
        n = _n(2.2); t = _t(n)
        m = _metal6(t; scale = 1.45)
        x = bandpass!(copy(m), 7800, 1.5) .+ 0.3 .* bandpass!(copy(m), 4200, 2.0)
        highpass!(x, 4000)
        return finish(x .* (0.7 .* _env(t, 0.5) .+ 0.3 .* _env(t, 0.05)))
    elseif id == "RideBell"
        # the famous 808 cowbell: two squares at 540/800 Hz through a bandpass
        n = _n(0.7); t = _t(n)
        x = _sq(540, t) .+ _sq(800, t)
        bandpass!(x, 2640, 1.8)
        lowpass!(x, 5000)
        return finish(x .* (0.65 .* _env(t, 0.035) .+ 0.35 .* _env(t, 0.22)))
    elseif id == "Crash"
        n = _n(3.0); t = _t(n)
        m = _metal6(t; scale = 1.3)
        x = bandpass!(copy(m), 6200, 0.8) .+ 0.25 .* highpass!(_noise(rng, n), 7000)
        highpass!(x, 3500)
        return finish(x .* min.(1.0, t ./ 0.0015) .* _env(t, 0.9))
    end
    error("Unbekanntes Instrument $id")
end

# --- 909 style --------------------------------------------------------------

"Coarse 6-bit quantization (character of the 909 cymbal ROMs)."
_bits6(x) = round.(x .* 31) ./ 31

function sound_909(id::AbstractString)
    rng = MersenneTwister(hash((909, id)))
    if id == "Kick"
        # fast pitch sweep, click and punch
        n = _n(0.8); t = _t(n)
        f = 52 .+ 190 .* _env(t, 0.018) .+ 40 .* _env(t, 0.09)
        click = bandpass!(_noise(rng, n), 3500, 0.8) .* _env(t, 0.0025)
        x = _sweep(f) .* (0.85 .* _env(t, 0.28) .+ 0.15 .* _env(t, 0.03)) .+ 0.35 .* click
        return finish(_sat(x, 2.2))
    elseif id == "Snare"
        n = _n(0.5); t = _t(n)
        f1 = 190 .* (1 .+ 0.3 .* _env(t, 0.02)); f2 = 280 .* (1 .+ 0.3 .* _env(t, 0.02))
        tone = (0.7 .* _sweep(f1) .+ 0.4 .* _sweep(f2)) .* _env(t, 0.06)
        nz = _noise(rng, n)
        snappy = highpass!(copy(nz), 2500) .* _env(t, 0.16) .+ 0.4 .* lowpass!(nz, 6000) .* _env(t, 0.05)
        return finish(_sat(tone .+ 0.9 .* snappy, 1.5))
    elseif id == "Rim"
        n = _n(0.07); t = _t(n)
        x = (sin.(2π * 1900 .* t) .+ 0.5 .* sin.(2π * 520 .* t) .+ 0.4 .* bandpass!(_noise(rng, n), 4000, 2.0)) .*
            _env(t, 0.007)
        return finish(x)
    elseif id in ("HiHat", "HHOpen", "HHPedal")
        dec = id == "HiHat" ? 0.05 : id == "HHOpen" ? 0.45 : 0.025
        n = _n(dec * 8); t = _t(n)
        x = 0.6 .* _metal6(t; scale = 1.9) .+ _noise(rng, n)
        bandpass!(x, 9500, 0.9)
        highpass!(x, 7000)
        x = _bits6(x ./ maximum(abs, x))
        return finish(x .* _env(t, dec); peak = id == "HHPedal" ? 0.6 : 1.0)
    elseif id in ("Tom", "FloorTom")
        f0 = id == "Tom" ? 185.0 : 105.0
        n = _n(0.8); t = _t(n)
        f = f0 .* (1 .+ 0.45 .* _env(t, 0.05))
        nz = lowpass!(_noise(rng, n), 3000) .* _env(t, 0.03)
        return finish(_sat(_sweep(f) .* _env(t, 0.25) .+ 0.18 .* nz, 1.3))
    elseif id in ("Ride", "RideBell", "Crash")
        dec = id == "Ride" ? 1.1 : id == "RideBell" ? 0.9 : 1.6
        n = _n(dec * 3); t = _t(n)
        if id == "RideBell"
            x = sum(a .* sin.(2π * f .* t) for (f, a) in ((650, 1.0), (1530, 0.7), (2470, 0.5), (3610, 0.3))) .+
                0.3 .* _metal6(t; scale = 2.5)
            bandpass!(x, 2400, 0.7)
        else
            x = _metal6(t; scale = id == "Ride" ? 2.8 : 2.2) .+ (id == "Crash" ? 1.2 : 0.5) .* _noise(rng, n)
            bandpass!(x, id == "Ride" ? 8500 : 7000, 0.6)
            highpass!(x, 4500)
        end
        x = _bits6(x ./ maximum(abs, x))
        return finish(x .* min.(1.0, t ./ 0.001) .* _env(t, dec))
    end
    error("Unbekanntes Instrument $id")
end

# --- Kits -------------------------------------------------------------------

# Level match to the acoustic kits (synth sounds are very dense, especially the kick)
const ANALOG_GAIN = 0.42

function analog_kit(name, sound, gain)
    layers = [[[Sample(sound(id))]] for id in TRACK_IDS]
    pan = Float32[0, 0, 0.1, -0.25, -0.25, -0.25, -0.2, 0.25, 0.3, 0.2, -0.3]
    choke = [0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0]
    # Synth sounds have only one layer: dynamics via level (accent like on the machine)
    return Kit(name, layers, pan, Float32.(ANALOG_GAIN .* gain), choke, (0.45f0, 0.75f0, 1.0f0))
end

"Kit in the style of the TR-808 (Ride Bell = cowbell)."
kit_808() = analog_kit("808 (Synth)", sound_808,
                       [1.0, 0.75, 0.6, 0.45, 0.45, 0.35, 0.8, 0.85, 0.35, 0.45, 0.4])

"Kit in the style of the TR-909."
kit_909() = analog_kit("909 (Synth)", sound_909,
                       [1.0, 0.8, 0.6, 0.4, 0.4, 0.3, 0.75, 0.8, 0.35, 0.4, 0.4])
