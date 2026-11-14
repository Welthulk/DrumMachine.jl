# Kleine DSP-Bausteine: Offline-Filter für die Klangsynthese und
# Echtzeit-Effekte (Reverb, Echo, Drive, Lo-Fi) für den Master-Bus.

const SR = 44100          # Abtastrate [Hz]

# ---------------------------------------------------------------------------
# Offline-Filter (arbeiten in-place auf Vektoren, nur für die Synthese)
# ---------------------------------------------------------------------------

"Einpoliger Tiefpass, in-place."
function lowpass!(x::AbstractVector{<:Real}, fc::Real)
    a = exp(-2π * fc / SR)
    y = 0.0
    @inbounds for i in eachindex(x)
        y = (1 - a) * x[i] + a * y
        x[i] = y
    end
    return x
end

"Einpoliger Hochpass (x - Tiefpass(x)), in-place."
function highpass!(x::AbstractVector{<:Real}, fc::Real)
    a = exp(-2π * fc / SR)
    y = 0.0
    @inbounds for i in eachindex(x)
        y = (1 - a) * x[i] + a * y
        x[i] -= y
    end
    return x
end

"RBJ-Biquad-Bandpass (konstante Spitzenverstärkung 0 dB), in-place."
function bandpass!(x::AbstractVector{<:Real}, f0::Real, Q::Real)
    w0 = 2π * f0 / SR
    α = sin(w0) / (2Q)
    b0, b1, b2 = α, 0.0, -α
    a0, a1, a2 = 1 + α, -2cos(w0), 1 - α
    b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
    x1 = x2 = y1 = y2 = 0.0
    @inbounds for i in eachindex(x)
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, xi
        y2, y1 = y1, yi
        x[i] = yi
    end
    return x
end

"Bitcrusher + Sample-and-Hold-Downsampling, in-place."
function crush!(x::AbstractVector{<:Real}, bits::Int, down::Int)
    if down > 1
        @inbounds for i in eachindex(x)
            j = i - (i - 1) % down
            x[i] = x[j]
        end
    end
    if bits > 0
        q = 2.0^(bits - 1)
        @inbounds for i in eachindex(x)
            x[i] = round(x[i] * q) / q
        end
    end
    return x
end

"Normiert auf Spitzenwert `peak` und blendet die letzten `fade` Sekunden aus."
function finish(x::AbstractVector{<:Real}; peak = 1.0, fade = 0.005)
    m = maximum(abs, x)
    y = Float32.(m > 0 ? x .* (peak / m) : x)
    nf = min(length(y), round(Int, fade * SR))
    @inbounds for k in 1:nf
        y[end-nf+k] *= Float32(1 - k / nf)
    end
    return y
end

# ---------------------------------------------------------------------------
# Echtzeit-Effekte (allokationsfrei pro Sample)
# ---------------------------------------------------------------------------

mutable struct Comb
    buf::Vector{Float32}
    idx::Int
    fb::Float32
    damp::Float32
    store::Float32
end
Comb(n, fb, damp) = Comb(zeros(Float32, n), 1, fb, damp, 0f0)

@inline function process(c::Comb, x::Float32)
    y = @inbounds c.buf[c.idx]
    c.store = y * (1f0 - c.damp) + c.store * c.damp
    @inbounds c.buf[c.idx] = x + c.store * c.fb
    c.idx = c.idx == length(c.buf) ? 1 : c.idx + 1
    return y
end

mutable struct Allpass
    buf::Vector{Float32}
    idx::Int
end
Allpass(n) = Allpass(zeros(Float32, n), 1)

@inline function process(a::Allpass, x::Float32)
    b = @inbounds a.buf[a.idx]
    @inbounds a.buf[a.idx] = x + b * 0.5f0
    a.idx = a.idx == length(a.buf) ? 1 : a.idx + 1
    return b - x
end

"Freeverb-artiger Stereo-Hall (4 Kammfilter + 2 Allpässe je Kanal)."
struct Reverb
    combL::Vector{Comb}
    combR::Vector{Comb}
    apL::Vector{Allpass}
    apR::Vector{Allpass}
end

function Reverb(roomsize::Real, damp::Real)
    sizes = (1116, 1188, 1277, 1356)
    fb = Float32(roomsize)
    d = Float32(damp)
    Reverb([Comb(s, fb, d) for s in sizes],
           [Comb(s + 23, fb, d) for s in sizes],
           [Allpass(556), Allpass(441)],
           [Allpass(579), Allpass(464)])
end

@inline function process(r::Reverb, l::Float32, rr::Float32)
    inp = (l + rr) * 0.015f0
    ol = 0f0; or = 0f0
    for c in r.combL; ol += process(c, inp); end
    for c in r.combR; or += process(c, inp); end
    for a in r.apL; ol = process(a, ol); end
    for a in r.apR; or = process(a, or); end
    return ol, or
end

function clear!(r::Reverb)
    for c in (r.combL..., r.combR...); fill!(c.buf, 0f0); c.store = 0f0; end
    for a in (r.apL..., r.apR...); fill!(a.buf, 0f0); end
    return r
end

"Ping-Pong-Echo mit tempoabhängiger Verzögerung."
mutable struct PingPong
    bufL::Vector{Float32}
    bufR::Vector{Float32}
    idx::Int
    delay::Int            # in Samples
    fb::Float32
    lp::Float32           # Zustand Tiefpass im Feedback
end
PingPong() = PingPong(zeros(Float32, 2SR), zeros(Float32, 2SR), 1, SR ÷ 4, 0.45f0, 0f0)

@inline function process(p::PingPong, l::Float32, r::Float32)
    n = length(p.bufL)
    j = p.idx - p.delay
    j < 1 && (j += n)
    dl = @inbounds p.bufL[j]
    dr = @inbounds p.bufR[j]
    p.lp = 0.7f0 * p.lp + 0.3f0 * dr           # Echos werden dunkler
    @inbounds p.bufL[p.idx] = (l + r) * 0.5f0 + p.lp * p.fb
    @inbounds p.bufR[p.idx] = dl * p.fb
    p.idx = p.idx == n ? 1 : p.idx + 1
    return dl, dr
end

clear!(p::PingPong) = (fill!(p.bufL, 0f0); fill!(p.bufR, 0f0); p.lp = 0f0; p)

const FX_NAMES = ["Clean", "Room", "Hall", "Echo", "Drive", "Lo-Fi"]

"Zustand des Master-Effekts. `kind` indiziert `FX_NAMES`, `mix` ∈ [0,1]."
mutable struct FXState
    kind::Int
    mix::Float32
    room::Reverb
    hall::Reverb
    echo::PingPong
    holdL::Float32
    holdR::Float32
    holdcnt::Int
end
FXState() = FXState(1, 0.3f0, Reverb(0.80, 0.35), Reverb(0.92, 0.2), PingPong(), 0f0, 0f0, 0)

function clear!(fx::FXState)
    clear!(fx.room); clear!(fx.hall); clear!(fx.echo)
    return fx
end

@inline function process(fx::FXState, l::Float32, r::Float32)
    k = fx.kind
    m = fx.mix
    if k == 2 || k == 3
        wl, wr = process(k == 2 ? fx.room : fx.hall, l, r)
        return l + m * wl, r + m * wr
    elseif k == 4
        wl, wr = process(fx.echo, l, r)
        return l + m * wl, r + m * wr
    elseif k == 5
        g = 1f0 + 9f0 * m
        n = tanh(g)
        return tanh(g * l) / n, tanh(g * r) / n
    elseif k == 6
        # Sample-and-Hold auf bis zu 1/8 Rate + Quantisierung
        down = 1 + round(Int, 7 * m)
        if fx.holdcnt <= 0
            fx.holdL = l; fx.holdR = r; fx.holdcnt = down
        end
        fx.holdcnt -= 1
        q = 2f0^(12 - round(Int, 8 * m))
        return round(fx.holdL * q) / q, round(fx.holdR * q) / q
    end
    return l, r
end

# ---------------------------------------------------------------------------
# Resampling
# ---------------------------------------------------------------------------

"""
    resample_sinc(x, fs_in, fs_out; taps = 32) -> Vector{Float32}

Bandbegrenztes Resampling mit Blackman-gefensterter Sinc-Interpolation (±`taps` Stützstellen).
Vermeidet das Aliasing linearer Interpolation, das vor allem Becken verfärbt.
"""
function resample_sinc(x::AbstractVector{<:Real}, fs_in::Real, fs_out::Real; taps::Int = 32)
    round(Int, fs_in) == round(Int, fs_out) && return Float32.(x)
    r = fs_out / fs_in
    fc = min(1.0, r) * 0.95                 # Grenzfrequenz relativ zur Eingangs-Nyquist
    n = length(x)
    m = floor(Int, n * r)
    y = Vector{Float32}(undef, m)
    @inbounds for k in 0:m-1
        t = k / r
        i0 = floor(Int, t)
        acc = 0.0
        for j in max(0, i0 - taps + 1):min(n - 1, i0 + taps)
            d = t - j
            w = 0.42 + 0.5 * cospi(d / taps) + 0.08 * cospi(2d / taps)
            acc += x[j+1] * fc * sinc(fc * d) * w
        end
        y[k+1] = acc
    end
    return y
end
