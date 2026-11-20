# Calibration windows ("Einmessen"): live view while the take runs, result view with the hits,
# old and new thresholds and the timing. The take itself is run by the main window (src/gui.jl),
# the evaluation is in src/midi.jl.

"Points shown per track in the live view."
const CAL_LIVE_N = 32

"Tracks with hits in pattern `p` (those a take can measure), in track order, at most 4."
cal_tracks(p::Pattern) = first([t for t in 1:NTRACKS if any(!iszero, @view p.grid[t, 1:p.steps])], 4)

_alpha(c, a) = RGBAf(c.r, c.g, c.b, a)
_signed_ms(x) = (ms = round(Int, x); ms > 0 ? "+$ms" : string(ms))

"Color of a hit with programmed level `l` (1 ghost, 2 normal, 3 accent)."
cal_color(l) = C_LEVEL_H[clamp(l, 1, 3)]

"""
    cal_live_figure(take, tracks, cfg; title) -> (fig, tick!)

Live view of a calibration take: phase in large letters (readable from the drum kit), the last hits
per track (velocity, colored by the programmed level, grey during the warm-up) with the current
thresholds, hits measured so far and the typical timing. `tick!()` reads `take` again.
"""
function cal_live_figure(take::CalTake, tracks::Vector{Int}, cfg::MidiConfig; title::AbstractString = "")
    fig = Figure(size = (1000, 640), backgroundcolor = C_BG, fontsize = 16, figure_padding = 20)
    hdr = fig[1, 1] = GridLayout(tellwidth = false, halign = :left)
    Label(hdr[1, 1], L("EINMESSEN"), font = :bold, fontsize = 24, color = C_TEXT)
    Label(hdr[1, 2], title, fontsize = 16, color = C_TEXT2, padding = (14, 0, 0, 0))

    panel!(fig[2, 1])
    top = fig[2, 1] = GridLayout(alignmode = Outside(18))
    phase_txt = Observable(""); phase_col = Observable(C_TEXT2); sub_txt = Observable("")
    Label(top[1, 1], phase_txt, fontsize = 46, font = :bold, color = phase_col, halign = :left, tellwidth = false)
    Label(top[2, 1], sub_txt, fontsize = 22, color = C_TEXT, halign = :left, tellwidth = false)

    panel!(fig[3, 1])
    mid = fig[3, 1] = GridLayout(alignmode = Outside(18))
    pts = [Observable(Point2f[]) for _ in tracks]
    cols = [Observable(RGBAf[]) for _ in tracks]
    heads = [Observable("") for _ in tracks]
    for (k, t) in enumerate(tracks)
        ax = Axis(mid[1, k]; title = heads[k], titlecolor = C_TEXT, titlesize = 18, height = 230,
                  backgroundcolor = C_INPUT, limits = (0.5, CAL_LIVE_N + 0.5, 0, 128),
                  xticksvisible = false, xticklabelsvisible = false, yticks = [0, 32, 64, 96, 127],
                  yticklabelcolor = C_TEXT2, ylabel = k == 1 ? "Velocity" : "", ylabelcolor = C_TEXT2,
                  xgridvisible = false, ygridcolor = C_LINE, leftspinecolor = C_LINE, rightspinecolor = C_LINE,
                  topspinecolor = C_LINE, bottomspinecolor = C_LINE)
        g, a = cfg.levels[t]
        hlines!(ax, [g, a]; color = C_TEXT2, linestyle = :dash, linewidth = 1.5)
        scatter!(ax, pts[k]; color = cols[k], markersize = 13)
        for i in (:rectanglezoom, :scrollzoom, :dragpan, :limitreset)
            try deregister_interaction!(ax, i) catch end
        end
    end
    leg = rich(L("Farbe = Stufe im Raster: "),
               (rich("● " * L(n) * "   "; color = cal_color(l)) for (l, n) in enumerate(("Ghost", "normal", "Akzent")))...,
               L("   ·   grau = Einspielen   ·   gestrichelt = bisherige Grenzen"); color = C_TEXT2)
    Label(mid[2, 1:length(tracks)], leg, fontsize = 14)

    foot = fig[4, 1] = GridLayout(tellwidth = false, halign = :left)
    foot_txt = Observable("")
    Label(foot[1, 1], foot_txt, fontsize = 18, color = C_TEXT2)
    rowgap!(fig.layout, 12)

    function tick!()
        now = time()
        ph = cal_phase(take, now)
        hs = take.hits
        n = count(h -> h.measured, hs)
        if ph == :wait
            set_if_changed!(phase_txt, L("Warte auf den ersten Schlag …"))
            set_if_changed!(phase_col, C_TEXT2)
            set_if_changed!(sub_txt, L("Das Pattern läuft. Geh in Ruhe ans Schlagzeug, setz die Kopfhörer auf und fang an, wenn du so weit bist."))
        elseif ph == :warmup
            left = ceil(Int, take.t_first + take.warmup - now)
            set_if_changed!(phase_txt, L("Einspielen – Messung beginnt in {1} s", left))
            set_if_changed!(phase_col, C_SOLO)
            set_if_changed!(sub_txt, L("Hör dich in den Groove ein. Laut und leise wie im Raster."))
        else
            set_if_changed!(phase_txt, L("Messung läuft · {1} Schläge", n))
            set_if_changed!(phase_col, C_ACTIVE)
            idle = now - max(take.t_last, take.t_first + take.warmup)
            set_if_changed!(sub_txt, idle > 2 ? L("Pause erkannt – Ende in {1} s", max(0, ceil(Int, CAL_IDLE_S - idle))) :
                                                L("Spiel weiter. {1} s Pause beenden die Messung.", round(Int, CAL_IDLE_S)))
        end
        for (k, t) in enumerate(tracks)
            ts = [h for h in hs if h.track == t]
            last_ = ts[max(1, end - CAL_LIVE_N + 1):end]
            p = [Point2f(i, h.vel) for (i, h) in enumerate(last_)]
            pts[k][] == p || (pts[k][] = p; cols[k][] = [h.measured ? RGBAf(cal_color(h.level)) : RGBAf(C_DIM) for h in last_])
            set_if_changed!(heads[k], "$(L(TRACKS[t][2])) · $(count(h -> h.measured, ts))")
        end
        ms = [h.ms for h in hs if h.measured]
        set_if_changed!(foot_txt, isempty(ms) ? L("Stop im Hauptfenster bricht ab.") :
            L("Timing im Mittel {1} ms (positiv = nach dem Beat)   ·   Stop im Hauptfenster bricht ab.", _signed_ms(_median(ms))))
        return nothing
    end
    tick!()
    return fig, tick!
end

"""
    cal_result_figure(res; apply!, discard!) -> (fig, buttons)

Result view: per track the measured hits along the velocity axis (rows ghost/normal/accent, red =
would get another level with the new thresholds), the new thresholds (solid) and the old ones
(dashed), the share of hits recognized before and after; the timing as a histogram. The buttons
call `apply!()` or `discard!()`.
"""
function cal_result_figure(res::CalResult; apply! = () -> nothing, discard! = () -> nothing)
    tracks = sort!(unique([h.track for h in res.hits]))
    nt = max(length(tracks), 1)
    fig = Figure(size = (1150, 260 + 150nt + 170), backgroundcolor = C_BG, fontsize = 15, figure_padding = 20)
    hdr = fig[1, 1] = GridLayout(tellwidth = false, halign = :left)
    Label(hdr[1, 1], L("EINMESSEN – ERGEBNIS"), font = :bold, fontsize = 24, color = C_TEXT)
    Label(hdr[1, 2], L("{1} Schläge gemessen", length(res.hits)), fontsize = 16, color = C_TEXT2, padding = (14, 0, 0, 0))

    panel!(fig[2, 1])
    box = fig[2, 1] = GridLayout(alignmode = Outside(18))
    zone = (_alpha(C_LEVEL[1], 0.18), _alpha(C_LEVEL[2], 0.14), _alpha(C_LEVEL[3], 0.12))
    for (k, t) in enumerate(tracks)
        old = res.before.levels[t]
        new = get(res.levels, t, old)
        hs = [h for h in res.hits if h.track == t]
        ax = Axis(box[k, 2]; height = 120, width = 560, backgroundcolor = C_INPUT, limits = (0, 128, 0.4, 3.6),
                  yticks = (1:3, [L("Ghost"), L("normal"), L("Akzent")]), yticklabelcolor = C_TEXT2,
                  xticks = 0:16:128, xticklabelcolor = C_TEXT2, xlabel = k == length(tracks) ? "Velocity" : "",
                  xlabelcolor = C_TEXT2, xgridvisible = false, ygridvisible = false,
                  leftspinecolor = C_LINE, rightspinecolor = C_LINE, topspinecolor = C_LINE, bottomspinecolor = C_LINE)
        for i in (:rectanglezoom, :scrollzoom, :dragpan, :limitreset)
            try deregister_interaction!(ax, i) catch end
        end
        g, a = new
        vspan!(ax, [0, g, a], [g, a, 128]; color = collect(zone))
        jit(i) = 0.3 * (((i * 0.618034) % 1) - 0.5) * 2              # fixed jitter, no randomness
        ok = [velocity_level(h.vel, new...) == h.level for h in hs]
        scatter!(ax, [Point2f(h.vel, h.level + jit(i)) for (i, h) in enumerate(hs)];
                 color = [o ? RGBAf(cal_color(h.level)) : RGBAf(C_MUTE) for (o, h) in zip(ok, hs)],
                 markersize = 9, strokewidth = 0)
        vlines!(ax, collect(old); color = C_TEXT2, linestyle = :dash, linewidth = 1.5)
        vlines!(ax, [g, a]; color = C_TEXT, linewidth = 2.5)
        r0, r1 = cal_hit_rate(res.hits, t, old), cal_hit_rate(res.hits, t, new)
        info = haskey(res.levels, t) ?
            L("Ghost unter {1}, Akzent ab {2}\nbisher {3} / {4}\nrichtig erkannt: {5} % (bisher {6} %)",
              g, a, old[1], old[2], round(Int, 100r1), round(Int, 100r0)) :
            L("zu wenig Schläge ({1}), bleibt {2} / {3}", length(hs), old[1], old[2])
        Label(box[k, 1], L(TRACKS[t][2]), font = :bold, fontsize = 18, color = C_TEXT, halign = :left, width = 90)
        Label(box[k, 3], info, fontsize = 15, color = haskey(res.levels, t) ? C_TEXT : C_TEXT2, halign = :left,
              justification = :left, width = 300)
    end
    isempty(tracks) && Label(box[1, 1], L("Keine Schläge gemessen."), fontsize = 18, color = C_TEXT2)
    Label(box[length(tracks)+1, 2], L("Linie = neue Grenze, gestrichelt = bisher, rot = Schlag bekäme eine andere Stufe"),
          fontsize = 13, color = C_TEXT2)

    panel!(fig[3, 1])
    tbox = fig[3, 1] = GridLayout(alignmode = Outside(18))
    ms = [h.ms for h in res.hits]
    tax = Axis(tbox[1, 2]; height = 110, width = 560, backgroundcolor = C_INPUT, limits = (-100, 100, 0, nothing),
               xlabel = L("ms neben dem Step (positiv = nach dem Beat)"), xlabelcolor = C_TEXT2,
               xticklabelcolor = C_TEXT2, yticksvisible = false, yticklabelsvisible = false,
               xgridvisible = false, ygridvisible = false, leftspinecolor = C_LINE, rightspinecolor = C_LINE,
               topspinecolor = C_LINE, bottomspinecolor = C_LINE)
    for i in (:rectanglezoom, :scrollzoom, :dragpan, :limitreset)
        try deregister_interaction!(tax, i) catch end
    end
    isempty(ms) || hist!(tax, clamp.(ms, -99.9, 99.9); bins = -100:5:100, color = _alpha(C_LEVEL[2], 0.8))
    vlines!(tax, [0]; color = C_TEXT2, linestyle = :dash)
    vlines!(tax, [res.median_ms]; color = C_TEXT, linewidth = 2.5)
    Label(tbox[1, 1], "Timing", font = :bold, fontsize = 18, color = C_TEXT, halign = :left, width = 90)
    Label(tbox[1, 3], res.offset === nothing ?
              L("im Mittel {1} ms\npasst, bleibt bei {2} ms", _signed_ms(res.median_ms), res.before.offset_ms) :
              L("im Mittel {1} ms\nmidi_offset_ms: {2} → {3}", _signed_ms(res.median_ms), res.before.offset_ms, res.offset),
          fontsize = 15, color = C_TEXT, halign = :left, justification = :left, width = 300)

    bb = fig[4, 1] = GridLayout(tellwidth = false, halign = :right)
    can = !isempty(res.levels) || res.offset !== nothing
    buttons = Button[]
    if can
        push!(buttons, Button(bb[1, 1], label = L("Verwerfen"), width = 140, height = 40))
        push!(buttons, Button(bb[1, 2], label = L("Übernehmen"), width = 160, height = 40, font = :bold,
                              buttoncolor = C_ACTIVE, buttoncolor_hover = C_ACT_DIM, labelcolor = C_BG))
        on(_ -> discard!(), buttons[1].clicks)
        on(_ -> apply!(), buttons[2].clicks)
    else
        push!(buttons, Button(bb[1, 1], label = L("Schließen"), width = 140, height = 40))
        on(_ -> discard!(), buttons[1].clicks)
    end
    rowgap!(fig.layout, 12)
    return fig, buttons
end

"""
    show_cal_live(take, tracks, cfg; title) -> screen

Opens the live window of a take; it updates itself until it is closed.
"""
function show_cal_live(take::CalTake, tracks::Vector{Int}, cfg::MidiConfig; title::AbstractString = "")
    fig, tick! = with_theme(() -> cal_live_figure(take, tracks, cfg; title), DM_THEME)
    screen = display(GLMakie.Screen(; title = L("DrumMachine – Einmessen")), fig)
    set_icon!(screen)
    @async while isopen(screen)
        try tick!() catch e; @error "calibration window" exception = e; break end
        sleep(1 / 30)
    end
    return screen
end

"""
    show_cal_result(res; apply!, discard!) -> screen

Opens the result window. A button calls `apply!` or `discard!` and closes the window; closing it
otherwise counts as discard.
"""
function show_cal_result(res::CalResult; apply! = () -> nothing, discard! = () -> nothing)
    decided = Ref(false)
    screen = Ref{Any}(nothing)
    done(f) = () -> (decided[] || (decided[] = true; f()); screen[] === nothing || close(screen[]))
    fig, _ = with_theme(() -> cal_result_figure(res; apply! = done(apply!), discard! = done(discard!)), DM_THEME)
    screen[] = display(GLMakie.Screen(; title = L("DrumMachine – Einmessen: Ergebnis")), fig)
    set_icon!(screen[])
    @async begin
        while isopen(screen[]); sleep(0.1); end
        decided[] || (decided[] = true; discard!())
    end
    return screen[]
end
