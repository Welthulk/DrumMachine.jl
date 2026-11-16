# Setup player and setup editor windows (see src/player.jl for the audio, src/setlist.jl for
# the setup files). The player runs on its own (`DrumMachine.player()`, `start_drum.sh
# --player`) or from the main window, where it shares the engine and the sound card.

const PLAYER_ROWS = 24                    # entries shown in the player and the editor
const PLAYER_CTX = Ref{Any}(nothing)      # state of the open player window (editor reloads it)

"Player master settings from the settings file (table `player`)."
function player_conf()
    d = get(load_settings(), "player", Dict{String,Any}())
    d isa AbstractDict || (d = Dict{String,Any}())
    num(k, lo, hi, def) = (v = get(d, k, def); v isa Real ? clamp(Float64(v), lo, hi) : Float64(def))
    hall = something(findfirst(==(get(d, "hall", "Aus")), PLAYER_HALLS), 1)
    return (gain_db = num("gain_db", -30, 6, 0),
            eq = (num("eq_low", -12, 12, 0), num("eq_mid", -12, 12, 0),
                  num("eq_midf", 200, 6000, EQ_MIDF_DEFAULT), num("eq_high", -12, 12, 0)),
            hall, hall_mix = num("hall_mix", 0, 1, 0.25), beep = num("beep", 0, 1, 1),
            route = something(findfirst(==(get(d, "route", "")), PLAYER_ROUTES), 1),
            auto = get(d, "auto", true) !== false,
            setlist = string(get(d, "setlist", "")))
end

fmt_pause(x) = isinteger(x) ? string(Int(x)) : string(round(x, digits = 1))
parse_pause(s) = (v = tryparse(Float64, replace(strip(s), "," => ".")); v === nothing || v < 0 || v > 600 ? nothing : v)

"""
    show_player(eng; standalone = false) -> screen

Opens the setup player. Loads the last used setup and prepares its songs in the background.
`standalone`: closing the window also stops the audio (the player was started on its own).
"""
function show_player(eng::Engine; standalone::Bool = false)
    pl = eng.player
    conf = player_conf()
    lock(eng.lock) do
        pl.auto = conf.auto; pl.gain = Float32(10^(conf.gain_db / 20))
        player_eq!(pl, conf.eq...); pl.hall = conf.hall; pl.hallmix = Float32(conf.hall_mix)
        pl.beepgain = Float32(conf.beep); pl.route = conf.route
    end
    ctx = player_context(eng; gain_db = conf.gain_db, eq = conf.eq)
    name = conf.setlist
    path = setlist_path(name)
    isempty(name) || !isfile(path) || (ctx.sl[] = try load_setlist(path) catch; Setlist() end)
    player_use!(ctx, ctx.sl[])
    fig, tick! = with_theme(() -> player_figure(ctx), DM_THEME)
    ctx.tick[] = tick!
    screen = display(GLMakie.Screen(; title = L("DrumMachine – Setup-Player")), fig)
    ctx.screen[] = screen
    PLAYER_CTX[] = ctx
    set_icon!(screen)
    @async begin
        while isopen(screen)
            ctx.tick[]()
            sleep(1 / 10)
        end
        lock(() -> player_stop!(pl), eng.lock)
        save_player_conf(ctx)
        standalone && stop_audio!(eng)
    end
    return screen
end

function save_player_conf(ctx)
    pl = ctx.eng.player
    save_setting!("player", player_settings(pl, ctx.eq[], ctx.gain_db[], ctx.sl[].name))
end

"State of a player window: setup, preparation progress, master values, screen."
player_context(eng::Engine; gain_db::Real = 0.0, eq = (0.0, 0.0, EQ_MIDF_DEFAULT, 0.0)) =
    (eng = eng, sl = Ref(Setlist()), ready = Ref(Bool[]), dur = Ref(Float64[]), err = Ref(String[]),
     gen = Ref(0), preparing = Ref(0), gain_db = Ref(Float64(gain_db)), eq = Ref(NTuple{4,Float64}(eq)),
     screen = Ref{Any}(nothing), tick = Ref{Function}(() -> nothing), editor = Ref{Any}(nothing))

"Waits (at most `timeout` s) until the songs of the player are prepared."
function wait_prepared(ctx; timeout::Real = 120)
    t0 = time()
    while ctx.preparing[] > 0 && time() - t0 < timeout
        sleep(0.05)
    end
    return ctx
end

"Player and editor figures for a setup, without window and audio (precompiling, screenshots)."
function player_figures(eng::Engine, sl::Setlist)
    ctx = player_context(eng)
    player_use!(ctx, sl); wait_prepared(ctx)
    pfig, ptick! = with_theme(() -> player_figure(ctx), DM_THEME)
    ptick!()
    efig = with_theme(() -> setlist_editor_figure((sl = Ref(copy_setlist(sl)), screen = Ref{Any}(nothing),
                                                    msg = Ref(""), on_saved = nothing)), DM_THEME)
    return ctx, pfig, ptick!, efig
end

"Puts setup `sl` into the player and prepares its songs in a background thread."
function player_use!(ctx, sl::Setlist)
    eng = ctx.eng; pl = eng.player
    ctx.sl[] = sl
    n = length(sl.entries)
    lock(() -> player_load!(pl, sl), eng.lock)
    ctx.ready[] = fill(false, n); ctx.dur[] = zeros(n); ctx.err[] = fill("", n)
    gen = (ctx.gen[] += 1)
    ctx.preparing[] = n
    Threads.@spawn for (i, e) in enumerate(sl.entries)
        ctx.gen[] == gen || return                       # another setup was loaded meanwhile
        try
            y, cue = prepare_entry_cue(e)
            ctx.gen[] == gen || return
            lock(eng.lock) do
                i <= length(pl.items) && (pl.items[i] = y; pl.cues[i] = cue)
            end
            ctx.dur[][i] = size(y, 1) / SR
            ctx.ready[][i] = true
        catch ex
            ctx.err[][i] = sprint(showerror, ex)
        end
        ctx.preparing[] = n - i
    end
    return ctx
end

"Rebuilds the player window (after loading or editing a setup)."
function player_rebuild!(ctx)
    fig, tick! = with_theme(() -> player_figure(ctx), DM_THEME)
    ctx.tick[] = tick!
    display(ctx.screen[], fig)
    return ctx
end

function player_load_name!(ctx, name::AbstractString)
    path = setlist_path(name)
    isfile(path) || return ctx
    player_use!(ctx, load_setlist(path))
    save_player_conf(ctx)
    player_rebuild!(ctx)
end

function player_figure(ctx)
    eng = ctx.eng; pl = eng.player; sl = ctx.sl[]
    n = min(length(sl.entries), PLAYER_ROWS)
    fig = Figure(size = (1200, 880), backgroundcolor = C_BG, fontsize = 14, figure_padding = 18)
    status = Observable("")

    # ---------------------------------------------------------------- header
    hdr = fig[1, 1] = GridLayout(halign = :left, tellwidth = false)
    Label(hdr[1, 1], L("SETUP-PLAYER"), font = :bold, fontsize = 22, color = C_TEXT, padding = (0, 14, 0, 0))
    names = list_setlists()
    opts = isempty(names) ? [L("– kein Setup –")] : names
    setmenu = Menu(hdr[1, 2], options = opts, default = sl.name in names ? sl.name : opts[1], width = 230)
    editbtn = Button(hdr[1, 3], label = L("Setup-Editor …"), buttoncolor = C_BTN_H)
    colgap!(hdr, 8)
    ctl = fig[2, 1] = GridLayout(halign = :left, tellwidth = false)
    autobtn = Button(ctl[1, 1], label = "Auto", width = 90, height = 40)
    manbtn = Button(ctl[1, 2], label = L("Manuell"), width = 100, height = 40)
    startbtn = Button(ctl[1, 3], label = L("▶ Setup starten"), height = 40, buttoncolor = C_ACTIVE, labelcolor = C_BG)
    stopbtn = Button(ctl[1, 4], label = "■ Stop", width = 100, height = 40)
    colgap!(ctl, 8); colgap!(ctl, 2, 24)
    Label(fig[3, 1], status, halign = :left, tellwidth = false, fontsize = 18, font = :bold, color = C_ACTIVE)

    # ---------------------------------------------------------------- song list
    body = fig[4, 1] = GridLayout(valign = :top, tellwidth = false, halign = :left)
    list = body[1, 1] = GridLayout(valign = :top, halign = :left)
    Label(list[1, 1], "#", color = C_TEXT2)
    Label(list[1, 2], L("Pause (s)"), color = C_TEXT2)
    Label(list[1, 3], "Beep", color = C_TEXT2)
    Label(list[1, 4], "Song", color = C_TEXT2, halign = :left)
    titles = [entry_title(e) for e in sl.entries[1:n]]
    songbtns = Button[]; beepbtns = Button[]
    for i in 1:n
        e = sl.entries[i]
        Label(list[i+1, 1], string(i), color = C_TEXT2, width = 28)
        tb = Textbox(list[i+1, 2], stored_string = fmt_pause(e.pause), width = 64,
                     validator = s -> parse_pause(s) !== nothing, reset_on_defocus = true)
        on(tb.stored_string) do s
            v = parse_pause(s); v === nothing && return
            e.pause = v
            lock(() -> (i <= length(pl.delays) && (pl.delays[i] = v)), eng.lock)
            save_setlist(sl)
        end
        bb = Button(list[i+1, 3], label = "♪", width = 44,
                    buttoncolor = e.beep ? C_ACTIVE : C_BTN, labelcolor = e.beep ? C_BG : C_TEXT)
        on(bb.clicks) do _
            e.beep = !e.beep
            lock(() -> (i <= length(pl.beeps) && (pl.beeps[i] = e.beep)), eng.lock)
            bb.buttoncolor[] = e.beep ? C_ACTIVE : C_BTN; bb.labelcolor[] = e.beep ? C_BG : C_TEXT
            save_setlist(sl)
        end
        sb = Button(list[i+1, 4], label = titles[i], width = 520, height = 30)
        on(sb.clicks) do _
            if !ctx.ready[][i]
                status[] = isempty(ctx.err[][i]) ? L("„{1}“ wird noch vorbereitet …", titles[i]) :
                           L("„{1}“ fehlt: {2}", titles[i], ctx.err[][i])
                return
            end
            lock(() -> player_start!(pl, i; pause = pl.auto), eng.lock)
        end
        push!(songbtns, sb); push!(beepbtns, bb)
    end
    if n == 0
        Label(list[2, 1:4], L("Noch kein Setup: im Setup-Editor Songs zusammenstellen und speichern."),
              color = C_TEXT2, halign = :left, word_wrap = true, width = 520, justification = :left)
        newbtn = Button(list[3, 1:4], label = L("Setup erstellen …"), height = 44, width = 260, halign = :left,
                        buttoncolor = C_ACTIVE, labelcolor = C_BG)
        on(_ -> editbtn.clicks[] += 1, newbtn.clicks)        # same as the editor button
    end
    length(sl.entries) > n && Label(list[n+2, 1:4], L("Nur die ersten {1} Einträge werden gezeigt.", PLAYER_ROWS),
                                    color = C_DIM, halign = :left)
    rowgap!(list, 4); colgap!(list, 8)
    colsize!(body, 1, Fixed(720))                      # the master stays to the right of the list

    # ---------------------------------------------------------------- master
    mbox = body[1, 2] = GridLayout(valign = :top, halign = :left)
    Label(mbox[1, 1:3], "MASTER", font = :bold, color = C_TEXT2, halign = :left)
    rows = Any[]
    function srow(r, name, rng, start, fmt, f)
        Label(mbox[r, 1], name, color = C_TEXT2, halign = :left)
        sl_ = Slider(mbox[r, 2], range = rng, startvalue = start, width = 160)
        Label(mbox[r, 3], lift(fmt, sl_.value), color = C_TEXT, halign = :left, width = 70, fontsize = 12)
        on(f, sl_.value)
        push!(rows, sl_)
        return sl_
    end
    db(v) = (v > 0 ? "+" : "") * "$(round(v, digits = 1)) dB"
    srow(2, L("Lautstärke"), -30:0.5:6, ctx.gain_db[], db, v -> begin
        ctx.gain_db[] = v; lock(() -> (pl.gain = Float32(10^(v / 20))), eng.lock)
    end)
    Label(mbox[3, 1:3], "EQ", color = C_DIM, fontsize = 12, halign = :left)
    midf_range = [200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6000]
    function seteq!(k, v)
        q = collect(ctx.eq[]); q[k] = Float64(v); ctx.eq[] = Tuple(q)
        lock(() -> player_eq!(pl, ctx.eq[]...), eng.lock)
    end
    srow(4, L("Tiefen"), -12:0.5:12, ctx.eq[][1], db, v -> seteq!(1, v))
    srow(5, L("Mitten"), -12:0.5:12, ctx.eq[][2], db, v -> seteq!(2, v))
    srow(6, L("Mitten bei"), midf_range, ctx.eq[][3],
         v -> v >= 1000 ? "$(round(v / 1000, digits = 1)) kHz" : "$(round(Int, v)) Hz", v -> seteq!(3, v))
    srow(7, L("Höhen"), -12:0.5:12, ctx.eq[][4], db, v -> seteq!(4, v))
    Label(mbox[8, 1], L("Hall"), color = C_TEXT2, halign = :left)
    hall_opts = Ls(PLAYER_HALLS)
    hallmenu = Menu(mbox[8, 2:3], options = hall_opts, default = hall_opts[pl.hall], width = 160)
    on(hallmenu.selection) do s
        k = something(findfirst(==(s), hall_opts), 1)
        lock(() -> (k != pl.hall && foreach(clear!, pl.halls); pl.hall = k), eng.lock)
    end
    srow(9, L("Anteil"), 0:0.01:1, pl.hallmix, v -> "$(round(Int, 100v)) %",
         v -> lock(() -> (pl.hallmix = Float32(v)), eng.lock))
    srow(10, L("Beep/Einzähler"), 0:0.05:1, pl.beepgain, v -> v == 0 ? L("aus") : "$(round(Int, 100v)) %",
         v -> lock(() -> (pl.beepgain = Float32(v)), eng.lock))
    Label(mbox[11, 1], L("Ausgang"), color = C_TEXT2, halign = :left)
    route_opts = Ls(PLAYER_ROUTES)
    routemenu = Menu(mbox[11, 2:3], options = route_opts, default = route_opts[pl.route], width = 230)
    on(routemenu.selection) do s
        k = something(findfirst(==(s), route_opts), 1)
        lock(() -> (pl.route = k), eng.lock)
    end
    Label(mbox[12, 1:3], L("Auto: Setup läuft mit Pausen und Beeps durch, Klick auf einen Song startet ab dort.\nManuell: Klick spielt den Song sofort, ohne Pause und Beep.\nDie Effekte der Songs bleiben erhalten, der Master wirkt zusätzlich.\nBeep/Einzähler: Countdown-Beeps und Einzähler der Songs; auf „aus“ läuft der Countdown nur in der Statuszeile.\nAusgang „Musik links, Beep rechts“: links zur PA, rechts auf den Kopfhörer."),
          color = C_DIM, fontsize = 12, halign = :left, justification = :left, padding = (0, 0, 0, 14),
          word_wrap = true, width = 330)
    rowgap!(mbox, 6); colgap!(mbox, 8)
    colgap!(body, 48)
    Label(fig[5, 1], ""; tellwidth = false, tellheight = false)      # spacer: content stays at the top
    rowsize!(fig.layout, 5, Auto(1))

    # ---------------------------------------------------------------- actions
    function show_mode!()
        autobtn.buttoncolor[] = pl.auto ? C_ACTIVE : C_BTN; autobtn.labelcolor[] = pl.auto ? C_BG : C_TEXT
        manbtn.buttoncolor[] = pl.auto ? C_BTN : C_ACTIVE; manbtn.labelcolor[] = pl.auto ? C_TEXT : C_BG
    end
    show_mode!()
    on(_ -> (lock(() -> (pl.auto = true), eng.lock); show_mode!()), autobtn.clicks)
    on(_ -> (lock(() -> (pl.auto = false), eng.lock); show_mode!()), manbtn.clicks)
    on(startbtn.clicks) do _
        isempty(sl.entries) && (status[] = L("Kein Setup geladen."); return)
        k = findfirst(ctx.ready[])
        k === nothing && (status[] = L("Die Songs werden noch vorbereitet …"); return)
        lock(() -> (pl.auto = true; player_start!(pl, k; pause = true)), eng.lock)
        show_mode!()
    end
    on(_ -> lock(() -> player_stop!(pl), eng.lock), stopbtn.clicks)
    on(setmenu.selection) do s
        s in names && s != sl.name && player_load_name!(ctx, s)
    end
    on(editbtn.clicks) do _
        w = ctx.editor[]
        w !== nothing && isopen(w) && return
        ctx.editor[] = show_setlist_editor(copy_setlist(sl); on_saved = player_reload!)
    end

    # ---------------------------------------------------------------- display
    last = Ref((-1, -1, -1, -1))
    function tick!()
        st = pl.shown_state[]; cur = pl.shown_cur[]
        ready = ctx.ready[]
        if st == 1
            w = pl.shown_wait[]
            secs = ceil(Int, w / SR)
            key = (st, cur, secs, 0)
            key != last[] && (status[] = L("Nächster Song: {1} · {2} – Start in {3} s", cur, get(titles, cur, ""), secs))
        elseif st == 2
            t = pl.shown_pos[] / SR
            key = (st, cur, floor(Int, t), 0)
            key != last[] && (status[] = "▶ $cur · $(get(titles, cur, ""))   $(fmt_time(t)) / $(fmt_time(get(ctx.dur[], cur, 0.0)))")
        else
            p = ctx.preparing[]
            key = (st, p, 0, 0)
            if key != last[]
                status[] = p > 0 ? L("Bereite die Songs vor … noch {1}", p) :
                           isempty(sl.entries) ? L("Kein Setup geladen.") :
                           L("Bereit: {1} – {2}", sl.name, pl.auto ? L("Auto") : L("Manuell"))
            end
        end
        last[] = key
        for (i, b) in enumerate(songbtns)                # colors: playing, waiting, ready, not ready
            c = (st == 2 && i == cur) ? C_ACTIVE : (st == 1 && i == cur) ? C_SOLO : C_BTN
            lc = (st == 2 && i == cur) ? C_BG : get(ready, i, false) ? C_TEXT : C_DIM
            b.buttoncolor[] == c || (b.buttoncolor[] = c)
            b.labelcolor[] == lc || (b.labelcolor[] = lc)
            if get(ready, i, false)
                lab = titles[i] * "   " * fmt_time(ctx.dur[][i])
                b.label[] == lab || (b.label[] = lab)
            elseif !isempty(get(ctx.err[], i, ""))
                lab = "⚠ " * titles[i]
                b.label[] == lab || (b.label[] = lab)
            end
        end
    end
    tick!()
    return fig, tick!
end

"After saving in the editor: the open player loads the saved setup."
function player_reload!(s::Setlist)
    ctx = PLAYER_CTX[]
    (ctx === nothing || ctx.screen[] === nothing || !isopen(ctx.screen[])) && return
    player_use!(ctx, s); save_player_conf(ctx); player_rebuild!(ctx)
end

"Opens the setup editor with the setup used last (from the main window)."
function show_setlist_editor_last()
    name = player_conf().setlist
    p = setlist_path(name)
    sl = !isempty(name) && isfile(p) ? (try load_setlist(p) catch; Setlist() end) : Setlist()
    return show_setlist_editor(sl; on_saved = player_reload!)
end

copy_setlist(sl::Setlist) = Setlist(sl.name, [SetEntry(e.path, e.pause, e.beep) for e in sl.entries])

"""
    show_setlist_editor(sl = Setlist(); on_saved = nothing) -> screen

Opens the setup editor: add songs (.toml) or audio files (.wav), change the order, save the setup.
`on_saved(sl)` is called after saving (the player then reloads the setup).
"""
function show_setlist_editor(sl::Setlist = Setlist(); on_saved = nothing)
    state = (sl = Ref(sl), screen = Ref{Any}(nothing), msg = Ref(""), on_saved = on_saved)
    fig = with_theme(() -> setlist_editor_figure(state), DM_THEME)
    screen = display(GLMakie.Screen(; title = L("DrumMachine – Setup-Editor")), fig)
    state.screen[] = screen
    set_icon!(screen)
    return screen
end

function editor_rebuild!(state)
    fig = with_theme(() -> setlist_editor_figure(state), DM_THEME)
    display(state.screen[], fig)
end

function setlist_editor_figure(state)
    sl = state.sl[]
    fig = Figure(size = (980, 860), backgroundcolor = C_BG, fontsize = 14, figure_padding = 18)
    status = Observable(state.msg[])
    hdr = fig[1, 1] = GridLayout(halign = :left, tellwidth = false)
    Label(hdr[1, 1], L("SETUP-EDITOR"), font = :bold, fontsize = 22, color = C_TEXT, padding = (0, 14, 0, 0))
    Label(hdr[1, 2], "Name", color = C_TEXT2)
    nametb = Textbox(hdr[1, 3], stored_string = sl.name, width = 220, reset_on_defocus = false)
    savebtn = Button(hdr[1, 4], label = L("Speichern"), buttoncolor = C_ACTIVE, labelcolor = C_BG)
    newbtn = Button(hdr[1, 5], label = L("Neu"))
    names = list_setlists()
    loadmenu = Menu(hdr[1, 6], options = vcat([L("Setup laden …")], names), width = 210)
    colgap!(hdr, 8)

    add = fig[2, 1] = GridLayout(halign = :left, tellwidth = false)
    songs = list_songs()
    songmenu = Menu(add[1, 1], options = vcat([L("Song hinzufügen …")], songs), width = 380)
    filebtn = Button(add[1, 2], label = L("Dateien hinzufügen (TOML/WAV) …"))
    colgap!(add, 8)

    list = fig[3, 1] = GridLayout(valign = :top, halign = :left, tellwidth = false)
    n = min(length(sl.entries), 30)
    Label(list[1, 1], "#", color = C_TEXT2); Label(list[1, 2], "Song", color = C_TEXT2, halign = :left)
    Label(list[1, 3], L("Datei"), color = C_TEXT2, halign = :left)
    function move!(i, d)
        j = i + d
        1 <= j <= length(sl.entries) || return
        sl.entries[i], sl.entries[j] = sl.entries[j], sl.entries[i]
        editor_rebuild!(state)
    end
    for i in 1:n
        e = sl.entries[i]
        f = entry_file(e)
        Label(list[i+1, 1], string(i), color = C_TEXT2, width = 28)
        Label(list[i+1, 2], entry_title(e), halign = :left, width = 300,
              color = isfile(f) ? C_TEXT : C_MUTE)
        Label(list[i+1, 3], (isfile(f) ? "" : "⚠ ") * basename(f), halign = :left, width = 330,
              color = C_DIM, fontsize = 12)
        up = Button(list[i+1, 4], label = "↑", width = 34); dn = Button(list[i+1, 5], label = "↓", width = 34)
        rm = Button(list[i+1, 6], label = "✕", width = 34)
        on(_ -> move!(i, -1), up.clicks); on(_ -> move!(i, 1), dn.clicks)
        on(rm.clicks) do _
            deleteat!(sl.entries, i); editor_rebuild!(state)
        end
    end
    n == 0 && Label(list[2, 1:3], L("Noch leer: Songs aus der Liste oder Dateien hinzufügen, dann speichern."),
                    color = C_TEXT2, halign = :left)
    length(sl.entries) > n && Label(list[n+2, 1:3], L("… und {1} weitere", length(sl.entries) - n), color = C_DIM)
    rowgap!(list, 4); colgap!(list, 8)
    Label(fig[4, 1], status, halign = :left, tellwidth = false, color = C_TEXT2)
    Label(fig[5, 1], L("Pausen und Beeps stellst du im Player vor jedem Song ein. Setups liegen in {1}", Base.contractuser(setlist_dir())),
          halign = :left, tellwidth = false, color = C_DIM, fontsize = 12)
    Label(fig[6, 1], ""; tellwidth = false, tellheight = false)      # spacer: content stays at the top
    rowsize!(fig.layout, 6, Auto(1))
    rowgap!(fig.layout, 12)

    on(nametb.stored_string) do s
        s = strip(s); isempty(s) || (sl.name = String(s))
    end
    on(savebtn.clicks) do _
        nm = strip(something(nametb.displayed_string[], sl.name))
        isempty(nm) || (sl.name = String(nm))
        p = save_setlist(sl)
        state.msg[] = L("Gespeichert: {1}", p); status[] = state.msg[]
        state.on_saved === nothing || state.on_saved(copy_setlist(sl))
    end
    on(newbtn.clicks) do _
        state.sl[] = Setlist(); state.msg[] = ""; editor_rebuild!(state)
    end
    on(loadmenu.selection) do s
        s in names || return
        state.sl[] = load_setlist(setlist_path(s)); state.msg[] = L("Geladen: {1}", s); editor_rebuild!(state)
    end
    on(songmenu.selection) do s
        s in songs || return
        f = song_file(s); isfile(f) || return
        push!(sl.entries, SetEntry(f)); state.msg[] = L("Hinzugefügt: {1}", s); editor_rebuild!(state)
    end
    on(filebtn.clicks) do _
        @async begin
            paths = pick_files(song_dir(); title = L("Songs oder WAV-Dateien hinzufügen"), exts = ("toml", "wav"),
                               kind = L("Songs und Audio"))
            if paths === nothing
                status[] = L("Kein Datei-Dialog gefunden – bitte zenity oder kdialog installieren.")
            elseif !isempty(paths)
                loops = filter(is_loop_file, paths)
                ok = filter(!is_loop_file, paths)
                append!(sl.entries, SetEntry.(ok))
                state.msg[] = L("{1} Dateien hinzugefügt.", length(ok)) *
                              (isempty(loops) ? "" : "  " * L("Loop-WAVs nicht übernommen (laufen endlos): {1}",
                                                               join(basename.(loops), ", ")))
                editor_rebuild!(state)
            end
        end
    end
    return fig
end

"""
    player(; block = true)

Starts only the setup player (for the stage), without the main window.
"""
function player(; block::Bool = true)
    GLMakie.activate!(title = "DrumMachine.jl")
    set_lang!(initial_lang())
    eng = Engine(Song(), synth_kit())                       # no GC pause: the player only plays finished audio
    start_audio!(eng; latency = max(audio_latency(), 0.15))   # no live input: a larger buffer is safer
    screen = show_player(eng; standalone = true)
    block && (wait(screen); sleep(0.5))            # let the window task save the settings and stop the audio
    return screen
end
