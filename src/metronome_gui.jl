# Metronome window: tempo (slider, field, tap), time signature, subdivision, accents, sound,
# gap training and tempo trainer. Plays through the engine of the main window (src/metronome.jl).

"""
    metronome_figure(eng) -> (fig, tick!)

Builds the metronome window for the engine `eng` (without displaying it).
"""
function metronome_figure(eng::Engine)
    m = eng.metro
    fig = Figure(size = (940, 560), backgroundcolor = C_BG, fontsize = 14, figure_padding = 18)
    HINT = L("Leertaste: Start/Stop · ↑/↓: ±1 BPM · T: Tap-Tempo · Einstellungen wirken ab dem nächsten Takt")
    status = Observable(HINT)
    setm!(f) = lock(f, eng.lock)                     # change settings safely while audio runs

    hdr = fig[1, 1] = GridLayout(tellwidth = false, halign = :left)
    Label(hdr[1, 1], L("METRONOM"), font = :bold, fontsize = 22, color = C_TEXT)
    Label(hdr[1, 2], L("Klick zum Üben, unabhängig vom Song"), fontsize = 14, color = C_TEXT2,
          padding = (14, 0, 0, 0))

    # ---------------------------------------------------------------- display
    panel!(fig[2, 1])
    disp = fig[2, 1] = GridLayout(alignmode = Outside(16))
    bpm_big = Label(disp[1:2, 1], string(round(Int, m.bpm)), fontsize = 72, font = :bold, color = C_TEXT,
                    width = 170, halign = :right)
    Label(disp[1:2, 2], "BPM", fontsize = 18, color = C_TEXT2, valign = :bottom, padding = (6, 20, 14, 0))
    ind = Axis(disp[1, 3]; height = 90, backgroundcolor = :transparent, BARE_AXIS...)
    for k in (:rectanglezoom, :scrollzoom, :dragpan, :limitreset)
        try deregister_interaction!(ind, k) catch end
    end
    pts = Observable(Point2f[]); sizes = Observable(Float32[]); cols = Observable(RGBAf[])
    strokes = Observable(RGBAf[])
    scatter!(ind, pts; markersize = sizes, color = cols, strokecolor = strokes, strokewidth = 3)
    info = Label(disp[2, 3], "", color = C_TEXT2, fontsize = 15, halign = :left)
    colgap!(disp, 0)

    # ---------------------------------------------------------------- controls
    panel!(fig[3, 1])
    ctl = fig[3, 1] = GridLayout(alignmode = Outside(16), halign = :left, tellwidth = false)
    r1 = ctl[1, 1] = GridLayout(halign = :left)
    startbtn = Button(r1[1, 1], label = "▶  Start", width = 110, buttoncolor = C_ACTIVE, labelcolor = C_BG,
                      buttoncolor_hover = C_LEVEL_H[2], labelcolor_hover = C_BG, labelcolor_active = C_BG,
                      font = :bold)
    steps = [Button(r1[1, k+1], label = (d > 0 ? "+" : "−") * string(abs(d)), width = 42)
             for (k, d) in enumerate((-5, -1))]
    bpm_sl = Slider(r1[1, 4], range = 30:1:400, startvalue = round(Int, m.bpm), width = 260)
    append!(steps, [Button(r1[1, k+4], label = "+" * string(d), width = 42) for (k, d) in enumerate((1, 5))])
    bpm_tb = Textbox(r1[1, 7], stored_string = string(round(Int, m.bpm)), width = 56,
                     validator = valid_bpm, reset_on_defocus = false)
    tapbtn = Button(r1[1, 8], label = "Tap", width = 60)
    songbtn = Button(r1[1, 9], label = L("Song-Tempo"))

    r2 = ctl[2, 1] = GridLayout(halign = :left)
    Label(r2[1, 1], L("Taktart"), color = C_TEXT2, halign = :right)
    meter_m = Menu(r2[1, 2], options = first.(METER_OPTS), default = METER_OPTS[m.meter][1], width = 150)
    Label(r2[1, 3], L("Unterteilung"), color = C_TEXT2, halign = :right)
    sub_opts = Ls(first.(SUBDIV_OPTS))
    sub_m = Menu(r2[1, 4], options = sub_opts, default = sub_opts[m.subdiv], width = 230)
    Label(r2[1, 5], L("Betonung"), color = C_TEXT2, halign = :right)
    acc_opts = Ls(ACCENT_OPTS)
    acc_m = Menu(r2[1, 6], options = acc_opts, default = acc_opts[m.accent], width = 170)

    r3 = ctl[3, 1] = GridLayout(halign = :left)
    Label(r3[1, 1], L("Klang"), color = C_TEXT2, halign = :right)
    snd_opts = Ls(SOUND_OPTS)
    snd_m = Menu(r3[1, 2], options = snd_opts, default = snd_opts[m.sound], width = 150)
    Label(r3[1, 3], L("Lautstärke"), color = C_TEXT2, halign = :right)
    vol_sl = Slider(r3[1, 4], range = 0:0.01:1, startvalue = m.vol, width = 140)
    Label(r3[1, 5], L("Unterteilung leiser/lauter"), color = C_TEXT2, halign = :right)
    sub_sl = Slider(r3[1, 6], range = 0:0.01:1, startvalue = m.subvol, width = 140)

    r4 = ctl[4, 1] = GridLayout(halign = :left)
    Label(r4[1, 1], L("Lücken-Training: spielen"), color = C_TEXT2, halign = :right)
    nums = string.(0:16)
    gp_m = Menu(r4[1, 2], options = nums, default = string(m.gap_play), width = 56)
    Label(r4[1, 3], L("Takte, stumm"), color = C_TEXT2)
    gm_m = Menu(r4[1, 4], options = nums, default = string(m.gap_mute), width = 56)
    Label(r4[1, 5], L("Takte"), color = C_TEXT2)

    r5 = ctl[5, 1] = GridLayout(halign = :left)
    Label(r5[1, 1], L("Tempo-Trainer: +"), color = C_TEXT2, halign = :right)
    tstep_opts = ["0", "1", "2", "3", "4", "5", "10"]
    ts_m = Menu(r5[1, 2], options = tstep_opts, width = 56,
                default = string(m.trainer_step) in tstep_opts ? string(m.trainer_step) : "0")
    Label(r5[1, 3], L("BPM alle"), color = C_TEXT2)
    tbars_opts = ["1", "2", "4", "8", "16"]
    tb_m = Menu(r5[1, 4], options = tbars_opts, width = 56,
                default = string(m.trainer_bars) in tbars_opts ? string(m.trainer_bars) : "4")
    Label(r5[1, 5], L("Takte bis"), color = C_TEXT2)
    tmax_tb = Textbox(r5[1, 6], stored_string = string(m.trainer_max), width = 56, validator = valid_bpm,
                      reset_on_defocus = false)
    Label(r5[1, 7], L("BPM  (0 = aus)"), color = C_TEXT2)
    rowgap!(ctl, 12)

    Label(fig[4, 1], status, halign = :left, tellwidth = false, color = C_TEXT2, fontsize = 13)
    rowgap!(fig.layout, 12)
    colsize!(fig.layout, 1, Relative(1))

    # ================================================================ logic
    function refresh_indicator!()
        _, np, groups = metro_meter(m)
        starts = cumsum([1; groups[1:end-1]])
        pts[] = [Point2f(p, 0) for p in 1:np]
        sizes[] = Float32[p == 1 ? 46 : p in starts ? 38 : 30 for p in 1:np]
        strokes[] = RGBAf[p in starts ? RGBAf(C_ACTIVE) : RGBAf(C_LINE) for p in 1:np]
        cols[] = fill(RGBAf(C_OFF_A), np)
        limits!(ind, 0.4, np + 0.6, -1, 1)
    end
    refresh_indicator!()

    function set_bpm_display!(v)
        bpm_big.text[] = string(v)
        str = string(v)
        bpm_tb.stored_string[] == str || (bpm_tb.stored_string[] = str)
        bpm_tb.focused[] || bpm_tb.displayed_string[] == str || (bpm_tb.displayed_string[] = str)
    end
    on(bpm_sl.value) do v
        setm!(() -> (m.bpm = v))
        set_bpm_display!(v)
    end
    on(bpm_tb.stored_string) do str
        valid_bpm(str) || return
        v = parse_bpm(str)
        bpm_sl.value[] == v || set_close_to!(bpm_sl, v)
    end
    commit_bpm!() = (str = bpm_tb.displayed_string[];
                     (str === nothing || str == bpm_tb.stored_string[]) && return;
                     valid_bpm(str) ? (bpm_tb.stored_string[] = str) : (bpm_tb.displayed_string[] = bpm_tb.stored_string[]))
    on(f -> f || commit_bpm!(), bpm_tb.focused)
    nudge!(d) = set_close_to!(bpm_sl, clamp(bpm_sl.value[] + d, 30, 400))
    for (b, d) in zip(steps, (-5, -1, 1, 5))
        on(_ -> nudge!(d), b.clicks)
    end
    taps = Float64[]
    function tap!()
        t = time()
        (!isempty(taps) && t - taps[end] > 2.0) && empty!(taps)
        push!(taps, t); length(taps) > 5 && popfirst!(taps)
        if length(taps) >= 2
            v = clamp(round(Int, 60 / ((taps[end] - taps[1]) / (length(taps) - 1))), 30, 400)
            set_close_to!(bpm_sl, v)
            status[] = L("Tap-Tempo: {1} BPM", v)
        end
    end
    on(_ -> tap!(), tapbtn.clicks)
    on(songbtn.clicks) do _
        set_close_to!(bpm_sl, clamp(round(Int, eng.song.bpm), 30, 400))
        status[] = L("Tempo vom Song übernommen: {1} BPM", round(Int, eng.song.bpm))
    end

    function toggle!()
        if m.on
            setm!(() -> metro_stop!(m))
            startbtn.label[] = "▶  Start"
        else
            setm!(() -> metro_start!(m))
            startbtn.label[] = "■  Stop"
        end
    end
    on(_ -> toggle!(), startbtn.clicks)

    pick(menu, opts) = (sel = menu.selection[]; sel === nothing ? nothing : findfirst(==(sel), opts))
    on(meter_m.selection) do _
        k = pick(meter_m, first.(METER_OPTS)); k === nothing && return
        setm!(() -> (m.meter = k)); refresh_indicator!()
    end
    on(sub_m.selection) do _
        k = pick(sub_m, sub_opts); k === nothing || setm!(() -> (m.subdiv = k))
    end
    on(acc_m.selection) do _
        k = pick(acc_m, acc_opts); k === nothing || setm!(() -> (m.accent = k))
    end
    on(snd_m.selection) do _
        k = pick(snd_m, snd_opts); k === nothing && return
        s = metro_sounds(k, eng.kit)                 # synthesize outside the audio lock
        setm!(() -> (m.sound = k; m.sounds = s))
    end
    on(v -> setm!(() -> (m.vol = Float32(v))), vol_sl.value)
    on(v -> setm!(() -> (m.subvol = Float32(v))), sub_sl.value)
    on(gp_m.selection) do sel
        sel === nothing || setm!(() -> (m.gap_play = parse(Int, sel)))
    end
    on(gm_m.selection) do sel
        sel === nothing && return
        setm!(() -> (m.gap_mute = parse(Int, sel)))
        m.gap_mute > 0 && m.gap_play == 0 && (gp_m.i_selected[] = 5)      # 4 bars on as a start
    end
    on(ts_m.selection) do sel
        sel === nothing || setm!(() -> (m.trainer_step = parse(Int, sel)))
    end
    on(tb_m.selection) do sel
        sel === nothing || setm!(() -> (m.trainer_bars = parse(Int, sel)))
    end
    on(tmax_tb.stored_string) do str
        valid_bpm(str) && setm!(() -> (m.trainer_max = parse_bpm(str)))
    end
    on(f -> f || (str = tmax_tb.displayed_string[]; str !== nothing && valid_bpm(str) &&
                  str != tmax_tb.stored_string[] && (tmax_tb.stored_string[] = str)), tmax_tb.focused)

    on(events(fig).keyboardbutton) do ev
        ev.action in (Keyboard.press, Keyboard.repeat) || return
        (bpm_tb.focused[] || tmax_tb.focused[]) && return
        if ev.key == Keyboard.space && ev.action == Keyboard.press
            toggle!()
        elseif ev.key == Keyboard.up
            nudge!(1)
        elseif ev.key == Keyboard.down
            nudge!(-1)
        elseif ev.key == Keyboard.t && ev.action == Keyboard.press
            tap!()
        end
    end

    # ---------------------------------------------------------------- display update
    last = Ref((-2, -2, false, false))
    kitref = Ref{Any}(eng.kit)
    function tick!()
        if eng.kit !== kitref[]                      # kit changed in the main window
            kitref[] = eng.kit
            if haskey(KIT_CLICKS, m.sound)
                snd = metro_sounds(m.sound, eng.kit)
                setm!(() -> (m.sounds = snd))
            end
        end
        v = round(Int, m.bpm)                        # tempo trainer changes the tempo
        bpm_sl.value[] == v || set_close_to!(bpm_sl, v)
        plen, np, _ = metro_meter(m)
        pulse = 0; bar = -1; muted = false
        if m.on && m.shown_bar[] >= 0
            bar = m.shown_bar[]
            pos = m.shown_pos[] - m.latency * m.bpm / 60      # what is audible right now
            barlen = plen * np
            pos < 0 && (pos += barlen; bar -= 1)
            if bar >= 0
                pulse = clamp(floor(Int, pos / plen) + 1, 1, np)
                muted = metro_muted(m, bar)
            end
        end
        cur = (pulse, bar, muted, m.on)
        cur == last[] && return
        last[] = cur
        length(cols[]) == np || refresh_indicator!()
        c = fill(RGBAf(C_OFF_A), np)
        pulse > 0 && (c[pulse] = muted ? RGBAf(C_DIM) : pulse == 1 ? RGBAf(C_LEVEL_H[3]) : RGBAf(C_ACTIVE))
        cols[] = c
        info.text[] = !m.on ? L("gestoppt") :
                      bar < 0 ? "" :
                      L("Takt {1}", bar + 1) * (muted ? "  ·  " * L("stumm – weiterzählen!") : "") *
                      (m.trainer_step > 0 ? "  ·  " * L("Trainer bis {1} BPM", m.trainer_max) : "")
    end
    tick!()
    return fig, tick!
end

"""
    show_metronome(eng) -> screen

Opens the metronome window. Its settings are loaded from and saved to the settings file; closing
the window stops the metronome.
"""
function show_metronome(eng::Engine)
    m = eng.metro
    m.on || lock(() -> metro_apply_settings!(m, get(load_settings(), "metronome", Dict{String,Any}()), eng.kit),
                 eng.lock)
    fig, tick! = with_theme(() -> metronome_figure(eng), DM_THEME)
    screen = display(GLMakie.Screen(; title = L("DrumMachine – Metronom")), fig)
    set_icon!(screen)
    @async begin
        while isopen(screen)
            tick!()
            sleep(1 / 60)
        end
        lock(() -> metro_stop!(m), eng.lock)
        save_setting!("metronome", metro_settings(m))
    end
    return screen
end
