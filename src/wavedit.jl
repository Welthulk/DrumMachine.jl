# WAV editor core (no GUI): audio model, destructive edits, effects, undo, waveform peaks.
# Ported and extended from SEdit (GTK4 editor). All functions work on a `Wave` with samples in rows
# and channels in columns (mono = N×1). Ranges are 1-based sample index ranges.

import WAV

"""
    Wave

Audio being edited: `data` is samples × channels (Float32, nominally -1…1), `fs` the sample rate.
`bits` is the bit depth of the source file and the default for saving.
"""
mutable struct Wave
    data::Matrix{Float32}
    fs::Int
    bits::Int
    path::String
end
Wave(data::AbstractMatrix, fs::Integer; bits::Integer = 16, path::AbstractString = "") =
    Wave(Matrix{Float32}(data), Int(fs), Int(bits), String(path))
Wave(data::AbstractVector, fs::Integer; kw...) = Wave(reshape(Vector{Float32}(data), :, 1), fs; kw...)

nframes(w::Wave) = size(w.data, 1)
nchan(w::Wave) = size(w.data, 2)
duration(w::Wave) = nframes(w) / w.fs
Base.copy(w::Wave) = Wave(copy(w.data), w.fs, w.bits, w.path)

"Clamps a range to the wave; returns an empty range if nothing is left."
function clamp_range(w::Wave, r::AbstractUnitRange)
    a = max(first(r), 1); b = min(last(r), nframes(w))
    return a:b
end

"Validated range for an edit: errors (German, shown in the GUI) if empty."
function edit_range(w::Wave, r::Union{Nothing,AbstractUnitRange})
    r === nothing && error(L("Keine Auswahl"))
    rr = clamp_range(w, r)
    isempty(rr) && error(L("Auswahl ist leer"))
    return rr
end

# ---------------------------------------------------------------------------
# File I/O
# ---------------------------------------------------------------------------

"""
    load_wave(path) -> Wave

Loads a WAV file (any PCM/float format WAV.jl can read). The bit depth becomes the default save
format: 16 and 24 bit are kept, 8 bit is saved as 16 bit and 32/64 bit as 32-bit float. Files with
more than two channels keep the first two (front left/right); the editor works on mono and stereo.
"""
function load_wave(path::AbstractString)
    y, fs, nbits, _ = WAV.wavread(path)
    fsi = round(Int, fs)
    isapprox(fs, fsi) || error(L("Abtastrate {1} wird nicht unterstützt", fs))
    size(y, 2) > 2 && (y = y[:, 1:2])
    bits = nbits in (16, 24) ? Int(nbits) : nbits < 16 ? 16 : 32
    return Wave(Matrix{Float32}(y), fsi; bits, path)
end

"""
    save_wave(path, w; bits = w.bits, range = nothing) -> path

Writes PCM (16/24 bit) or 32-bit float WAV. Samples are clamped to -1…1 for PCM (WAV.jl would
otherwise throw on values above full scale). Only `fmt` and `data` chunks are written, which is
what devices like the Roland TD-27 expect. `range` saves just that part (e.g. the selection).
"""
function save_wave(path::AbstractString, w::Wave; bits::Integer = w.bits,
                   range::Union{Nothing,AbstractUnitRange} = nothing)
    y = range === nothing ? w.data : w.data[edit_range(w, range), :]
    mkpath(dirname(abspath(path)))
    if bits == 32
        WAV.wavwrite(Float32.(y), path; Fs = w.fs, nbits = 32, compression = WAV.WAVE_FORMAT_IEEE_FLOAT)
    elseif bits in (16, 24)
        q = 2^(bits - 1) - 1
        pcm = round.(Int32, clamp.(y, -1f0, 1f0) .* q)
        WAV.wavwrite(bits == 16 ? Int16.(pcm) : pcm, path; Fs = w.fs, nbits = bits,
                     compression = WAV.WAVE_FORMAT_PCM)
    else
        error(L("Bittiefe {1} wird nicht unterstützt (16, 24 oder 32)", bits))
    end
    return path
end

# ---------------------------------------------------------------------------
# Edits (all return the wave; length-changing edits replace `w.data`)
# ---------------------------------------------------------------------------

"Removes the range (\"Löschen\")."   # i18n-ok: docstring quoting the German button
function delete_range!(w::Wave, r)
    rr = edit_range(w, r)
    w.data = vcat(w.data[1:first(rr)-1, :], w.data[last(rr)+1:end, :])
    return w
end

"Keeps only the range (\"Zuschneiden\" / trim)."
function crop!(w::Wave, r)
    w.data = w.data[edit_range(w, r), :]
    return w
end

"Sets the range to silence."
function silence!(w::Wave, r)
    w.data[edit_range(w, r), :] .= 0f0
    return w
end

"Fade shapes: linear, or equal-power (sine) which sounds smoother on drums."
fade_curve(x, curve::Symbol) = curve == :linear ? x : sinpi(x / 2)

"""
    fade_in!(w, r; curve = :linear)

Ramps the range from 0 to full level. Works for ranges of any length, including one sample
(SEdit threw an error there).
"""
function fade_in!(w::Wave, r; curve::Symbol = :linear)
    rr = edit_range(w, r); n = length(rr)
    for (k, i) in enumerate(rr)
        g = Float32(fade_curve(n == 1 ? 1.0 : (k - 1) / (n - 1), curve))
        @views w.data[i, :] .*= g
    end
    return w
end

"Ramps the range from full level to 0."
function fade_out!(w::Wave, r; curve::Symbol = :linear)
    rr = edit_range(w, r); n = length(rr)
    for (k, i) in enumerate(rr)
        g = Float32(fade_curve(n == 1 ? 0.0 : 1 - (k - 1) / (n - 1), curve))
        @views w.data[i, :] .*= g
    end
    return w
end

"Changes the level of the range by `db` decibels (no clipping; saving clamps)."
function gain!(w::Wave, r, db::Real)
    @views w.data[edit_range(w, r), :] .*= Float32(10.0^(db / 20))
    return w
end

"Scales the range so its peak is `peak_db` dBFS. A silent range is left unchanged."
function normalize!(w::Wave, r; peak_db::Real = -0.1)
    rr = edit_range(w, r)
    m = maximum(abs, @view w.data[rr, :])
    m > 0 && (@views w.data[rr, :] .*= Float32(10.0^(peak_db / 20) / m))
    return w
end

"Plays the range backwards."
function reverse!(w::Wave, r)
    rr = edit_range(w, r)
    w.data[rr, :] = w.data[reverse(rr), :]
    return w
end

"Inserts `secs` seconds of silence before sample `at` (1 … nframes+1)."
function insert_silence!(w::Wave, at::Integer, secs::Real)
    n = max(0, round(Int, secs * w.fs))
    n == 0 && return w
    i = clamp(at, 1, nframes(w) + 1)
    w.data = vcat(w.data[1:i-1, :], zeros(Float32, n, nchan(w)), w.data[i:end, :])
    return w
end

"Returns a copy of the range (clipboard)."
copy_range(w::Wave, r) = w.data[edit_range(w, r), :]

"Resamples frames × channels data from `fs_in` to `fs_out` (band-limited sinc)."
resample_frames(x::AbstractMatrix, fs_in, fs_out) =
    fs_in == fs_out ? Matrix{Float32}(x) : reduce(hcat, (resample_sinc(@view(x[:, c]), fs_in, fs_out) for c in 1:size(x, 2)))

"""
    paste!(w, at, clip)

Inserts `clip` (samples × channels, sample rate `fs`) before sample `at`. Mono clips are spread
to all channels, a stereo clip pasted into mono is mixed down, and a clip with another sample rate
is resampled so pitch and speed stay the same.
"""
function paste!(w::Wave, at::Integer, clip::AbstractMatrix; fs::Integer = w.fs)
    clip = resample_frames(clip, fs, w.fs)   # clip from a file with another sample rate
    c = size(clip, 2) == nchan(w) ? clip :
        size(clip, 2) == 1 ? repeat(clip, 1, nchan(w)) :
        repeat(sum(clip; dims = 2) ./ size(clip, 2), 1, nchan(w))
    i = clamp(at, 1, nframes(w) + 1)
    w.data = vcat(w.data[1:i-1, :], Float32.(c), w.data[i:end, :])
    return w
end

"Stereo → mono (average) or mono → stereo (duplicate)."
function set_channels!(w::Wave, n::Integer)
    nchan(w) == n && return w
    mono = sum(w.data; dims = 2) ./ nchan(w)
    w.data = n == 1 ? mono : repeat(nchan(w) == 1 ? w.data : mono, 1, n)
    return w
end

"""
    prepend_countin!(w; bpm, beats = 4, gain = 0.5)

Puts `beats` quarter-note clicks before the audio. The count-in is exactly `beats` beats long, so
the audio starts on the next beat (SEdit started it right after the last click). The first click
is accented (higher pitch).
"""
function prepend_countin!(w::Wave; bpm::Real, beats::Integer = 4, gain::Real = 0.5)
    bpm > 0 || error(L("BPM muss größer als 0 sein"))
    beats <= 0 && return w
    beat = round(Int, 60 * w.fs / bpm)
    clicklen = clamp(round(Int, 0.03 * w.fs), 1, beat)
    intro = zeros(Float32, beats * beat, nchan(w))
    for b in 0:beats-1
        f = b == 0 ? 1500.0 : 1000.0
        for k in 1:clicklen
            env = 1 - (k - 1) / clicklen
            intro[b*beat+k, :] .+= Float32(gain * env * sinpi(2f * (k - 1) / w.fs))
        end
    end
    w.data = vcat(intro, w.data)
    return w
end

"""
    estimate_bpm(w; min_bpm = 55, max_bpm = 220) -> Union{Int,Nothing}

Tempo estimate (quarter notes per minute). The energy envelope (5 ms frames) is autocorrelated;
each candidate beat period is scored by the correlation at 1, 2 and 4 beats (so 3:2 patterns such
as dotted quarters or 8th-note hi-hats do not win) and weighted with a broad preference for
tempos around 120 BPM. Tested on the example songs at 80/100/120 % tempo: 16 of 18 within 3 %
(SEdit's single-lag version: 8 of 18).
"""
function estimate_bpm(w::Wave; min_bpm::Real = 55, max_bpm::Real = 220)
    hop = max(1, round(Int, w.fs * 0.005))
    sig = vec(sum(abs2, w.data; dims = 2))
    nf = fld(length(sig), hop)
    nf < 16 && return nothing
    env = [Float64(sum(@view sig[(k-1)*hop+1:k*hop])) for k in 1:nf]
    env .-= sum(env) / nf
    env .= max.(env, 0)
    env .-= sum(env) / nf                  # centre again after clipping (sharper peaks)
    dt = hop / w.fs
    ac(l) = l >= nf - 1 ? 0.0 : sum(@view(env[1:end-l]) .* @view(env[1+l:end])) / (nf - l)
    lo = max(1, round(Int, 60 / max_bpm / dt)); hi = min(round(Int, 60 / min_bpm / dt), nf - 2)
    hi <= lo && return nothing
    best, score = 0, -Inf
    for l in lo:hi
        bpm = 60 / (l * dt)
        sc = (ac(l) + ac(2l) + ac(4l)) * exp(-0.5 * log2(bpm / 120)^2)
        sc > score && ((best, score) = (l, sc))
    end
    (best <= 0 || !(score > 0)) && return nothing
    # parabolic interpolation around the peak for sub-frame accuracy
    # Parabolic refinement, only if `best` is a local maximum of ac itself (the weighted score can
    # pick a lag in a flat region, where the parabola would extrapolate to nonsense).
    s0, s1, s2 = ac(best - 1), ac(best), ac(best + 1)
    den = s0 - 2s1 + s2
    lf = Float64(best)
    if den < 0 && s1 >= max(s0, s2)
        lf += clamp(0.5 * (s0 - s2) / den, -0.5, 0.5)
    end
    bpm = round(Int, 60 / (lf * dt))
    return min_bpm <= bpm <= max_bpm ? bpm : nothing
end

# ---------------------------------------------------------------------------
# Effects (offline, reusing the real-time DSP of the drum machine)
# ---------------------------------------------------------------------------

const WAVE_FX = ["Room", "Hall", "Echo", "Chorus", "Flanger", "Drive", "EQ"]
"Maximum decay in seconds an effect may add after the range (silence below -70 dB is trimmed)."
const WAVE_FX_TAIL = Dict("Room" => 2.0, "Hall" => 4.5, "Chorus" => 0.1, "Flanger" => 0.4)

"Echo delay in frames: one 8th note at `bpm`, limited by the echo buffer."
echo_delay(bpm, fs) = clamp(round(Int, 30 * fs / bpm), 1, 2SR - 1)

"Tail length in frames for effect `fx` (Echo: until the repeats are below -70 dB)."
fx_tail(fx, bpm, fs) = fx == "Echo" ? echo_delay(bpm, fs) * 12 + round(Int, 0.2fs) :
                       round(Int, get(WAVE_FX_TAIL, fx, 0.0) * fs)

"""
    apply_fx!(w, r, fx; mix = 0.5, eq = (0, 0, 800, 0), bpm = 120)

Runs effect `fx` (one of `WAVE_FX`) over the range. Reverb and echo tails ring on after the range
into the following audio; if the range ends at the end of the file, the file is extended by the
tail and trailing silence below -70 dB is removed. `eq` = (low dB, mid dB, mid Hz, high dB).
The echo time is one 8th note at `bpm`.
"""
function apply_fx!(w::Wave, r, fx::AbstractString; mix::Real = 0.5,
                   eq::NTuple{4,Real} = (0, 0, 800, 0), bpm::Real = 120)
    fx in WAVE_FX || error(L("Unbekannter Effekt {1}", fx))
    rr = edit_range(w, r)
    nchan(w) <= 2 || error(L("Effekte gehen nur bei Mono und Stereo"))
    tail = fx_tail(fx, bpm, w.fs)
    at_end = last(rr) == nframes(w)
    at_end && tail > 0 && (w.data = vcat(w.data, zeros(Float32, tail, nchan(w))))
    stop = min(last(rr) + tail, nframes(w))
    st = stereo_proc(fx, mix, eq, bpm, w.fs)
    for i in first(rr):stop
        inside = i <= last(rr)
        l = w.data[i, 1]; rch = w.data[i, nchan(w)]
        # outside the range only the effect's own tail is added (input = 0)
        il, ir = inside ? (l, rch) : (0f0, 0f0)
        ol, or = st(il, ir)
        if nchan(w) == 1
            v = (ol + or) / 2                     # stereo effects folded back to mono
            inside ? (w.data[i, 1] = v) : (w.data[i, 1] += v)
        elseif inside
            w.data[i, 1] = ol; w.data[i, 2] = or
        else
            w.data[i, 1] += ol; w.data[i, 2] += or
        end
    end
    at_end && tail > 0 && trim_tail!(w; from = last(rr) + 1)
    return w
end

"Removes trailing samples below -70 dB, but never before frame `from`."
function trim_tail!(w::Wave; from::Integer = 1)
    thr = 10f0^(-70 / 20)
    k = findlast(i -> maximum(abs, @view w.data[i, :]) > thr, 1:nframes(w))
    n = max(something(k, 0), from - 1)
    n < nframes(w) && (w.data = w.data[1:n, :])
    return w
end

"Builds a per-sample stereo processor `(l, r) -> (l, r)` for effect `fx` (wet/dry by `mix`)."
function stereo_proc(fx, mix, eq, bpm, fs)
    m = Float32(mix)
    if fx == "EQ"
        lo, mi, mf, hi = eq
        q = (design!(Biquad(), :low, EQ_LOW_F, lo; fs), design!(Biquad(), :peak, mf, mi; fs),
             design!(Biquad(), :high, EQ_HIGH_F, hi; fs))
        return (l, r) -> begin
            for b in q; l, r = process(b, l, r); end
            (l, r)
        end
    elseif fx in ("Room", "Hall")
        rv = fx == "Room" ? Reverb(0.80, 0.35; fs) : Reverb(0.92, 0.2; fs)
        return (l, r) -> ((wl, wr) = process(rv, l, r); (l + m * wl, r + m * wr))
    elseif fx == "Echo"
        pp = PingPong(); pp.delay = echo_delay(bpm, fs)
        return (l, r) -> ((wl, wr) = process(pp, l, r); (l + m * wl, r + m * wr))
    elseif fx in ("Chorus", "Flanger")
        md = ModDelay(fs); d = MOD_DEFAULTS[fx]
        return (l, r) -> process(md, fx == "Chorus", l, r, m, Float32(d.rate), Float32(d.depth), Float32(d.fb))
    else # Drive
        g = 1f0 + 9f0 * m; n = tanh(g)
        return (l, r) -> (tanh(g * l) / n, tanh(g * r) / n)
    end
end

# ---------------------------------------------------------------------------
# Undo / redo
# ---------------------------------------------------------------------------

"Snapshot history: full copies of the audio, `limit` steps back."
mutable struct History
    undo::Vector{Tuple{Matrix{Float32},String}}
    redo::Vector{Tuple{Matrix{Float32},String}}
    limit::Int
end
History(limit::Integer = 30) = History([], [], limit)

"Stores the state before an edit called `label`. Clears the redo stack."
function snapshot!(h::History, w::Wave, label::AbstractString)
    push!(h.undo, (copy(w.data), String(label)))
    length(h.undo) > h.limit && popfirst!(h.undo)
    empty!(h.redo)
    return h
end

"Undoes the last edit; returns its label or `nothing`."
function undo!(h::History, w::Wave)
    isempty(h.undo) && return nothing
    data, label = pop!(h.undo)
    push!(h.redo, (w.data, label))
    w.data = data
    return label
end

"Redoes the last undone edit; returns its label or `nothing`."
function redo!(h::History, w::Wave)
    isempty(h.redo) && return nothing
    data, label = pop!(h.redo)
    push!(h.undo, (w.data, label))
    w.data = data
    return label
end

# ---------------------------------------------------------------------------
# Waveform display
# ---------------------------------------------------------------------------

"""
    wave_peaks(w, ch, first, last, bins) -> (mins, maxs)

Min/max per bin for drawing channel `ch` between frames `first` and `last` (one bin per pixel
column). When zoomed in to fewer frames than bins, every frame is its own bin.
"""
function wave_peaks(w::Wave, ch::Integer, a::Integer, b::Integer, bins::Integer)
    a = max(a, 1); b = min(b, nframes(w))
    n = b - a + 1
    n <= 0 && return Float32[], Float32[]
    bins = clamp(bins, 1, n)
    mins = Vector{Float32}(undef, bins); maxs = Vector{Float32}(undef, bins)
    x = @view w.data[:, ch]
    @inbounds for k in 1:bins
        i0 = a + div((k - 1) * n, bins); i1 = a + div(k * n, bins) - 1
        lo = hi = x[i0]
        for i in i0+1:i1
            v = x[i]; v < lo && (lo = v); v > hi && (hi = v)
        end
        mins[k] = lo; maxs[k] = hi
    end
    return mins, maxs
end
