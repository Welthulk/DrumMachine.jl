# Small DSP building blocks: offline filters for sound synthesis and
# real-time effects (reverb, echo, drive, lo-fi) for the master bus,
# plus EQ and chorus/flanger per track.

const SR = 44100          # sample rate [Hz]

# ---------------------------------------------------------------------------
# Offline filters (work in-place on vectors, synthesis only)
# ---------------------------------------------------------------------------

"One-pole lowpass, in-place."
function lowpass!(x::AbstractVector{<:Real}, fc::Real)
    a = exp(-2π * fc / SR)
    y = 0.0
    @inbounds for i in eachindex(x)
        y = (1 - a) * x[i] + a * y
        x[i] = y
    end
    return x
end

"One-pole highpass (x - lowpass(x)), in-place."
function highpass!(x::AbstractVector{<:Real}, fc::Real)
    a = exp(-2π * fc / SR)
    y = 0.0
    @inbounds for i in eachindex(x)
        y = (1 - a) * x[i] + a * y
        x[i] -= y
    end
    return x
end

"RBJ biquad bandpass (constant 0 dB peak gain), in-place."
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

"Bitcrusher + sample-and-hold downsampling, in-place."
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

"Normalizes to peak value `peak` and fades out the last `fade` seconds."
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
# Real-time effects (allocation-free per sample)
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

"Freeverb-style stereo reverb (4 comb filters + 2 allpasses per channel)."
struct Reverb
    combL::Vector{Comb}
    combR::Vector{Comb}
    apL::Vector{Allpass}
    apR::Vector{Allpass}
end

function Reverb(roomsize::Real, damp::Real; fs::Real = SR)
    k = fs / 44100                     # delay lengths are tuned for 44.1 kHz
    n(x) = max(1, round(Int, x * k))
    sizes = (1116, 1188, 1277, 1356)
    fb = Float32(roomsize)
    d = Float32(damp)
    Reverb([Comb(n(s), fb, d) for s in sizes],
           [Comb(n(s + 23), fb, d) for s in sizes],
           [Allpass(n(556)), Allpass(n(441))],
           [Allpass(n(579)), Allpass(n(464))])
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

"Ping-pong echo with tempo-dependent delay."
mutable struct PingPong
    bufL::Vector{Float32}
    bufR::Vector{Float32}
    idx::Int
    delay::Int            # in samples
    fb::Float32
    lp::Float32           # lowpass state in the feedback path
end
PingPong() = PingPong(zeros(Float32, 2SR), zeros(Float32, 2SR), 1, SR ÷ 4, 0.45f0, 0f0)

@inline function process(p::PingPong, l::Float32, r::Float32)
    n = length(p.bufL)
    j = p.idx - p.delay
    j < 1 && (j += n)
    dl = @inbounds p.bufL[j]
    dr = @inbounds p.bufR[j]
    p.lp = 0.7f0 * p.lp + 0.3f0 * dr           # echoes get darker
    @inbounds p.bufL[p.idx] = (l + r) * 0.5f0 + p.lp * p.fb
    @inbounds p.bufR[p.idx] = dl * p.fb
    p.idx = p.idx == n ? 1 : p.idx + 1
    return dl, dr
end

clear!(p::PingPong) = (fill!(p.bufL, 0f0); fill!(p.bufR, 0f0); p.lp = 0f0; p)

const FX_NAMES = ["Clean", "Room", "Hall", "Echo", "Drive", "Lo-Fi"]

"State of the master effect. `kind` indexes `FX_NAMES`, `mix` ∈ [0,1]."
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
        # sample-and-hold down to 1/8 rate + quantization
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
# Track effects: 3-band EQ and chorus/flanger (per track, stereo, allocation-free)
# ---------------------------------------------------------------------------

"Stereo biquad (direct form I), coefficients from the RBJ Audio EQ Cookbook."
mutable struct Biquad
    b0::Float64; b1::Float64; b2::Float64; a1::Float64; a2::Float64
    xl1::Float64; xl2::Float64; yl1::Float64; yl2::Float64
    xr1::Float64; xr2::Float64; yr1::Float64; yr2::Float64
end
Biquad() = Biquad(1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

function set_coeffs!(q::Biquad, b0, b1, b2, a0, a1, a2)
    q.b0 = b0 / a0; q.b1 = b1 / a0; q.b2 = b2 / a0; q.a1 = a1 / a0; q.a2 = a2 / a0
    return q
end

"Shelf/bell: `kind` = :low, :peak or :high; `gain` in dB."
function design!(q::Biquad, kind::Symbol, f0::Real, gain::Real; Q::Real = 0.9, fs::Real = SR)
    f0 = min(f0, 0.45fs)               # stay below Nyquist for low sample rates
    A = 10.0^(gain / 40)
    w = 2π * f0 / fs
    c = cos(w); sn = sin(w)
    if kind == :peak
        α = sn / (2Q)
        set_coeffs!(q, 1 + α * A, -2c, 1 - α * A, 1 + α / A, -2c, 1 - α / A)
    else                                   # shelf with slope S = 1
        α = sn / 2 * sqrt(2)
        k = 2sqrt(A) * α
        if kind == :low
            set_coeffs!(q, A * ((A + 1) - (A - 1) * c + k), 2A * ((A - 1) - (A + 1) * c),
                        A * ((A + 1) - (A - 1) * c - k), (A + 1) + (A - 1) * c + k,
                        -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - k)
        else
            set_coeffs!(q, A * ((A + 1) + (A - 1) * c + k), -2A * ((A - 1) + (A + 1) * c),
                        A * ((A + 1) + (A - 1) * c - k), (A + 1) - (A - 1) * c + k,
                        2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - k)
        end
    end
    return q
end

@inline function process(q::Biquad, l::Float32, r::Float32)
    yl = q.b0 * l + q.b1 * q.xl1 + q.b2 * q.xl2 - q.a1 * q.yl1 - q.a2 * q.yl2
    q.xl2 = q.xl1; q.xl1 = l; q.yl2 = q.yl1; q.yl1 = yl
    yr = q.b0 * r + q.b1 * q.xr1 + q.b2 * q.xr2 - q.a1 * q.yr1 - q.a2 * q.yr2
    q.xr2 = q.xr1; q.xr1 = r; q.yr2 = q.yr1; q.yr1 = yr
    return Float32(yl), Float32(yr)
end

"Modulated delay for chorus (12-18 ms) and flanger (0.8-5 ms, with feedback)."
mutable struct ModDelay
    bufL::Vector{Float32}
    bufR::Vector{Float32}
    idx::Int
    phase::Float64
    fs::Float64
end
ModDelay(fs::Real = SR) = (n = ceil(Int, 2048 * fs / 44100);
                           ModDelay(zeros(Float32, n), zeros(Float32, n), 1, 0.0, Float64(fs)))

@inline function tap(buf::Vector{Float32}, idx::Int, d::Float64)
    n = length(buf)
    p = idx - d
    p < 1 && (p += n)
    i = unsafe_trunc(Int, p)
    f = Float32(p - i)
    j = i == n ? 1 : i + 1
    @inbounds return buf[i] * (1f0 - f) + buf[j] * f
end

"`chorus=true`: chorus, otherwise flanger. Output: (1 - mix/2)·dry + mix/2·wet."
@inline function process(m::ModDelay, chorus::Bool, l::Float32, r::Float32,
                         mix::Float32, rate::Float32, depth::Float32, fb::Float32)
    fs = m.fs
    m.phase += rate / fs
    m.phase >= 1 && (m.phase -= 1)
    if chorus
        base = 0.012 * fs; sweep = depth * 0.006 * fs; off = 0.25     # L/R phase-offset
    else
        base = 0.0008 * fs; sweep = depth * 0.0042 * fs; off = 0.08
    end
    dl = base + sweep * (0.5 + 0.5 * sinpi(2m.phase))
    dr = base + sweep * (0.5 + 0.5 * sinpi(2(m.phase + off)))
    wl = tap(m.bufL, m.idx, dl)
    wr = tap(m.bufR, m.idx, dr)
    @inbounds m.bufL[m.idx] = l + fb * wl
    @inbounds m.bufR[m.idx] = r + fb * wr
    m.idx = m.idx == length(m.bufL) ? 1 : m.idx + 1
    g = 0.5f0 * mix
    return (1f0 - g) * l + g * wl, (1f0 - g) * r + g * wr
end

const EQ_LOW_F = 120.0
const EQ_HIGH_F = 5000.0

"Effect state of a track. `key` remembers the EQ setting of the current coefficients."
mutable struct TrackFX
    low::Biquad
    mid::Biquad
    high::Biquad
    mod::ModDelay
    key::NTuple{4,Float32}
end
TrackFX() = TrackFX(Biquad(), Biquad(), Biquad(), ModDelay(), (0f0, 0f0, 0f0, 0f0))

function update_eq!(fx::TrackFX, low::Float32, mid::Float32, midf::Float32, high::Float32)
    key = (low, mid, midf, high)
    key == fx.key && return fx
    design!(fx.low, :low, EQ_LOW_F, low)
    design!(fx.mid, :peak, midf, mid)
    design!(fx.high, :high, EQ_HIGH_F, high)
    fx.key = key
    return fx
end

# ---------------------------------------------------------------------------
# Resampling
# ---------------------------------------------------------------------------

"""
    resample_sinc(x, fs_in, fs_out; taps = 32) -> Vector{Float32}

Band-limited resampling with Blackman-windowed sinc interpolation (±`taps` taps).
Avoids the aliasing of linear interpolation, which mainly colors cymbals.
"""
function resample_sinc(x::AbstractVector{<:Real}, fs_in::Real, fs_out::Real; taps::Int = 32)
    round(Int, fs_in) == round(Int, fs_out) && return Float32.(x)
    r = fs_out / fs_in
    fc = min(1.0, r) * 0.95                 # cutoff relative to the input Nyquist
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
