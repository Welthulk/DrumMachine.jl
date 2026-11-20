# Recording windows: the live window (tempo, grid and time signature, Start/Stop, phase in large
# letters, the bar being played) and the result (all bars at a glance, Apply/Discard). The take
# runs in the main window (src/gui.jl), the logic is in src/midi.jl.

"Beats per bar offered for a recording."
const REC_BEATS = 2:7

"Lengths offered for a recording in bars (0 = until a pause)."
const REC_LENGTHS = [0, 2, 4, 8, 12, 16, 24, 32]

"Settings of the recording window: tempo, steps per beat, beats per bar, length in bars (0 = free)."
mutable struct RecSetup
    bpm::Float64
    spb::Int
    beats::Int
    bars::Int
end
RecSetup(bpm, spb, beats) = RecSetup(bpm, spb, beats, 0)

"Steps of a bar, at most MAXSTEPS (fewer beats when a fine grid would not fit)."
rec_steps(s::RecSetup) = s.spb * min(s.beats, MAXSTEPS ÷ s.spb)

"""
    rec_live_figure(setup, take; start!, stop!) -> (fig, tick!)

Live window of a recording. `take()` returns the running `RecTake` or `nothing`; `start!()` is
called by *Start* (with `setup` filled in from the controls), `stop!()` by *Stop*.
"""
function rec_live_figure(setup::RecSetup, take::Function; start! = () -> nothing, stop! = () -> nothing)
    fig = Figure(size = (1000, 700), backgroundcolor = C_BG, fontsize = 16, figure_padding = 20)
    hdr = fig[1, 1] = GridLayout(tellwidth = false, halign = :left)
    Label(hdr[1, 1], L("AUFNAHME"), font = :bold, fontsize = 24, color = C_TEXT)
    Label(hdr[1, 2], L("in einen neuen Song, Takt für Takt"), fontsize = 16, color = C_TEXT2, padding = (14, 0, 0, 0))

    panel!(fig[2, 1])
    st = fig[2, 1] = GridLayout(alignmode = Outside(16), halign = :left, tellwidth = false)
    Label(st[1, 1], "BPM", color = C_TEXT2)
    bpm_sl = Slider(st[1, 2], range = 40:1:240, startvalue = clamp(round(Int, setup.bpm), 40, 240), width = 200)
    bpm_tb = Textbox(st[1, 3], stored_string = string(round(Int, setup.bpm)), width = 60, validator = valid_bpm,
                     reset_on_defocus = false)
    Label(st[1, 4], L("Raster"), color = C_TEXT2, padding = (16, 0, 0, 0))
    ropts = Ls(first.(RASTER_OPTS))
    rmenu = Menu(st[1, 5], options = ropts, width = 230,
                 default = ropts[something(findfirst(o -> o[2] == setup.spb, RASTER_OPTS), 1)])
    Label(st[2, 1], L("Takt"), color = C_TEXT2)
    topts = ["$b/4" for b in REC_BEATS]
    tmenu = Menu(st[2, 2], options = topts, width = 80, halign = :left, default = "$(clamp(setup.beats, extrema(REC_BEATS)...))/4")
    Label(st[2, 4], L("Länge"), color = C_TEXT2, padding = (16, 0, 0, 0))
    lopts = [n == 0 ? L("frei (bis zur Spielpause)") : L("{1} Takte", n) for n in REC_LENGTHS]
    lmenu = Menu(st[2, 5], options = lopts, width = 230,
                 default = lopts[something(findfirst(==(setup.bars), REC_LENGTHS), 1)])
    startbtn = Button(st[1:2, 6], label = "▶  Start", width = 150, height = 56, font = :bold, fontsize = 20,
                      buttoncolor = C_ACTIVE, buttoncolor_hover = C_ACT_DIM, labelcolor = C_BG)
    colgap!(st, 10); rowgap!(st, 10)
    syncing = Ref(false)
    on(bpm_sl.value) do v
        syncing[] && return
        setup.bpm = v
        syncing[] = true; bpm_tb.displayed_string[] = string(v); bpm_tb.stored_string[] = string(v); syncing[] = false
    end
    on(bpm_tb.stored_string) do str
        (str === nothing || syncing[]) && return
        setup.bpm = parse_bpm(str)
        syncing[] = true; set_close_to!(bpm_sl, clamp(setup.bpm, 40, 240)); syncing[] = false
    end
    on(lmenu.selection) do sel
        sel === nothing || (setup.bars = REC_LENGTHS[findfirst(==(sel), lopts)])
    end
    on(rmenu.selection) do sel
        sel === nothing || (setup.spb = RASTER_OPTS[findfirst(==(sel), ropts)][2])
    end
    on(tmenu.selection) do sel
        sel === nothing || (setup.beats = parse(Int, split(sel, '/')[1]))
    end
    on(startbtn.clicks) do _
        if take() === nothing
            str = bpm_tb.displayed_string[]                       # also without Enter
            valid_bpm(str) && (setup.bpm = parse_bpm(str))
            start!()
        else
            stop!()
        end
    end

    panel!(fig[3, 1])
    top = fig[3, 1] = GridLayout(alignmode = Outside(18))
    phase_txt = Observable(""); phase_col = Observable(C_TEXT2); sub_txt = Observable("")
    Label(top[1, 1], phase_txt, fontsize = 44, font = :bold, color = phase_col, halign = :left, tellwidth = false)
    Label(top[2, 1], sub_txt, fontsize = 21, color = C_TEXT, halign = :left, tellwidth = false)

    panel!(fig[4, 1])
    gbox = fig[4, 1] = GridLayout(alignmode = Outside(18))
    bar_title = Observable("")
    rects = Observable(Rect2f[]); rcols = Observable(RGBAf[])
    ax = Axis(gbox[1, 1]; title = bar_title, titlecolor = C_TEXT, titlesize = 18, height = 300,
              backgroundcolor = :transparent, limits = (0, 16, 0, NTRACKS),
              yticks = (NTRACKS .- (1:NTRACKS) .+ 0.5, [L(t[2]) for t in TRACKS]), yticklabelcolor = C_TEXT2,
              xticksvisible = false, xticklabelsvisible = false, xgridvisible = false, ygridvisible = false,
              leftspinevisible = false, rightspinevisible = false, topspinevisible = false, bottomspinevisible = false)
    for i in (:rectanglezoom, :scrollzoom, :dragpan, :limitreset)
        try deregister_interaction!(ax, i) catch end
    end
    poly!(ax, rects; color = rcols, strokewidth = 0)

    foot = fig[5, 1] = GridLayout(tellwidth = false, halign = :left)
    foot_txt = Observable("")
    Label(foot[1, 1], foot_txt, fontsize = 17, color = C_TEXT2)
    rowgap!(fig.layout, 12)

    shown = Ref((-2, -1, 0))                                  # (bar, hits, steps) drawn last
    function tick!()
        r = take()
        now = time()
        set_if_changed!(startbtn.label, r === nothing ? "▶  Start" : "■  Stop")
        if r === nothing
            set_if_changed!(phase_txt, L("Bereit"))
            set_if_changed!(phase_col, C_TEXT2)
            set_if_changed!(sub_txt, L("Tempo, Raster und Takt wählen, dann Start. Der Klick läuft, bis du spielst."))
            set_if_changed!(foot_txt, "")
            return nothing
        end
        if rec_phase(r) == :wait
            set_if_changed!(phase_txt, L("Warte auf den ersten Schlag …"))
            set_if_changed!(phase_col, C_TEXT2)
            set_if_changed!(sub_txt, L("Der Klick läuft. Geh in Ruhe ans Schlagzeug, setz die Kopfhörer auf und fang an, wenn du so weit bist."))
        else
            set_if_changed!(phase_txt, r.maxbars > 0 ? L("Aufnahme läuft · Takt {1} von {2}", min(rec_bars(r), r.maxbars), r.maxbars) :
                                                       L("Aufnahme läuft · Takt {1}", rec_bars(r)))
            set_if_changed!(phase_col, C_MUTE)
            idle = now - r.t_last
            set_if_changed!(sub_txt, r.maxbars > 0 ? L("Nach {1} Takten endet die Aufnahme von selbst.", r.maxbars) :
                                     idle > 2 ? L("Pause erkannt – Ende in {1} s", max(0, ceil(Int, REC_IDLE_S - idle))) :
                                                L("Spiel weiter. {1} s Pause beenden die Aufnahme.", round(Int, REC_IDLE_S)))
        end
        hs = r.hits
        if isempty(hs)
            b = -1
        else
            b = hs[end].bar
        end
        key = (b, length(hs), r.steps)
        if key != shown[]
            shown[] = key
            bh = [h for h in hs if h.bar == b]
            row(t) = NTRACKS - t + 0.12                       # kick on top, as in the main window
            rects[] = vcat([Rect2f(s - 1 + 0.06, row(t), 0.88, 0.76) for s in 1:r.steps for t in 1:NTRACKS],
                           [Rect2f(h.step - 1 + 0.06, row(h.track), 0.88, 0.76) for h in bh])
            rcols[] = vcat([RGBAf((s - 1) ÷ r.spb % 2 == 0 ? C_OFF_A : C_OFF_B) for s in 1:r.steps for _ in 1:NTRACKS],
                           [RGBAf(C_LEVEL[clamp(h.level, 1, 3)]) for h in bh])
            limits!(ax, 0, r.steps, 0, NTRACKS)
            b0 = isempty(hs) ? b : minimum(h.bar for h in hs)
            bar_title[] = b < 0 ? L("Takt") : L("Takt {1}", b - b0 + 1)
            ms = [h.ms for h in hs]
            foot_txt[] = isempty(ms) ? "" : L("{1} Schläge · Timing im Mittel {2} ms · Stop beendet die Aufnahme", length(hs), _signed_ms(_median(ms)))
        end
        return nothing
    end
    tick!()
    return fig, tick!
end

"""
    rec_result_figure(song, info; apply!, discard!) -> (fig, buttons)

Result of a recording: summary (bars, patterns, chain, hits, timing) and all bars at a glance
(tracks × steps, colored by level, pattern number above each bar).
"""
function rec_result_figure(song::Song, info; apply! = () -> nothing, discard! = () -> nothing,
                           labels = (L("Rückgängig"), L("OK")))
    used = [t for t in 1:NTRACKS if any(p -> any(!iszero, @view p.grid[t, 1:p.steps]), song.patterns)]
    isempty(used) && (used = [1])
    nt = length(used)
    fig = Figure(size = (1150, 330 + 26nt), backgroundcolor = C_BG, fontsize = 15, figure_padding = 20)
    hdr = fig[1, 1] = GridLayout(tellwidth = false, halign = :left)
    Label(hdr[1, 1], L("AUFNAHME – ERGEBNIS"), font = :bold, fontsize = 24, color = C_TEXT)
    Label(hdr[1, 2], L("{1} Takte · {2} Pattern · {3} Schläge · {4} BPM", info.bars, info.patterns, info.hits,
                       round(Int, song.bpm)), fontsize = 16, color = C_TEXT2, padding = (14, 0, 0, 0))

    panel!(fig[2, 1])
    box = fig[2, 1] = GridLayout(alignmode = Outside(18))
    steps = song.patterns[1].steps
    n = length(song.chain)
    ax = Axis(box[1, 1]; height = 26nt, width = 960, backgroundcolor = :transparent, yreversed = true,
              limits = (0, n * steps, 0, nt), yticks = ((1:nt) .- 0.5, [L(TRACKS[t][2]) for t in used]),
              yticklabelcolor = C_TEXT2, xticks = (((0:n-1) .+ 0.5) .* steps, ["$(k)\nP$(p)" for (k, p) in enumerate(song.chain)]),
              xticklabelcolor = C_TEXT2, xticklabelsize = n > 32 ? 9 : 13, xlabel = L("Takt und Pattern"), xlabelcolor = C_TEXT2,
              xgridvisible = false, ygridvisible = false, leftspinevisible = false, rightspinevisible = false,
              topspinevisible = false, bottomspinevisible = false)
    for i in (:rectanglezoom, :scrollzoom, :dragpan, :limitreset)
        try deregister_interaction!(ax, i) catch end
    end
    bg = Rect2f[]; bgc = RGBAf[]; fg = Rect2f[]; fgc = RGBAf[]
    for (k, pi) in enumerate(song.chain), s in 1:steps
        x = (k - 1) * steps + s - 1
        push!(bg, Rect2f(x + 0.05, 0, 0.9, nt)); push!(bgc, RGBAf(isodd(k) ? C_OFF_A : C_OFF_B))
        for (j, t) in enumerate(used)
            lv = song.patterns[pi].grid[t, s]
            lv > 0 && (push!(fg, Rect2f(x + 0.05, j - 1 + 0.1, 0.9, 0.8)); push!(fgc, RGBAf(C_LEVEL[lv])))
        end
    end
    poly!(ax, bg; color = bgc, strokewidth = 0)
    poly!(ax, fg; color = fgc, strokewidth = 0)
    Label(box[2, 1], L("Kette: {1}", chain_string(song.chain)), fontsize = 14, color = C_TEXT, halign = :left,
          tellwidth = false, word_wrap = true)
    notes = String[]
    push!(notes, L("Timing im Mittel {1} ms (positiv = nach dem Beat).", _signed_ms(info.median_ms)))
    info.merged > 0 && push!(notes, L("{1} Takte an ähnliche Pattern angeglichen (höchstens {2} Pattern).", info.merged, REC_MAX_PATTERNS))
    push!(notes, L("Die Aufnahme ist als neuer Song geladen, mit „Speichern“ sichern. „Rückgängig“ holt deinen vorherigen Song zurück."))
    Label(box[3, 1], join(notes, "\n"), fontsize = 14, color = C_TEXT2, halign = :left, justification = :left, tellwidth = false)

    bb = fig[3, 1] = GridLayout(tellwidth = false, halign = :right)
    buttons = [Button(bb[1, 1], label = labels[1], width = 140, height = 40),
               Button(bb[1, 2], label = labels[2], width = 160, height = 40, font = :bold,
                      buttoncolor = C_ACTIVE, buttoncolor_hover = C_ACT_DIM, labelcolor = C_BG)]
    on(_ -> discard!(), buttons[1].clicks)
    on(_ -> apply!(), buttons[2].clicks)
    rowgap!(fig.layout, 12)
    return fig, buttons
end

"""
    show_rec_live(setup, take; start!, stop!, closed!) -> screen

Opens the recording window; `closed!()` is called when it is closed.
"""
function show_rec_live(setup::RecSetup, take::Function; start! = () -> nothing, stop! = () -> nothing,
                       closed! = () -> nothing)
    fig, tick! = with_theme(() -> rec_live_figure(setup, take; start!, stop!), DM_THEME)
    screen = display(GLMakie.Screen(; title = L("DrumMachine – Aufnahme")), fig)
    set_icon!(screen)
    @async begin
        while isopen(screen)
            try tick!() catch e; @error "recording window" exception = e; break end
            sleep(1 / 30)
        end
        closed!()
    end
    return screen
end

"""
Opens the result window of a recording; the recording is already loaded. *Rückgängig* calls
`undo!()`, *OK* or closing the window keeps it.
"""
function show_rec_result(song::Song, info; undo! = () -> nothing)
    screen = Ref{Any}(nothing)
    closeit() = screen[] === nothing || close(screen[])
    fig, _ = with_theme(() -> rec_result_figure(song, info; apply! = closeit, discard! = () -> (undo!(); closeit())), DM_THEME)
    screen[] = display(GLMakie.Screen(; title = L("DrumMachine – Aufnahme: Ergebnis")), fig)
    set_icon!(screen[])
    return screen[]
end
