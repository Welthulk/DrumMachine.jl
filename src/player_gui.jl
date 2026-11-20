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
            setlist = string(get(d, "setlist", "")), midi_out = string(get(d, "midi_out", "")))
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
    ctx.midi_want[] = conf.midi_out                     # reopen the MIDI output of the last session
    ctx.midi_outs[] = midi_outputs()
    if !isempty(conf.midi_out)                          # a failure stays in the status line (midi_msg)
        conf.midi_out in ctx.midi_outs[] ? player_midi_out!(ctx, conf.midi_out) :
            (ctx.midi_msg[] = L("MIDI-Ausgang „{1}“ nicht gefunden, im Menü MIDI-Ausgang wählen.", conf.midi_out))
    end
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
        ctx.gen[] += 1                                   # stops the background preparation
        lock(() -> player_load!(pl, Setlist()), eng.lock)   # stops and drops all prepared audio
        save_player_conf(ctx)                            # first: closing the MIDI output takes a while
        try midi_out_close!(pl, eng.lock) catch e; @warn "MIDI output not closed" exception = e end
        PLAYER_CTX[] === ctx && (PLAYER_CTX[] = nothing)     # the main window waits for this
        standalone && stop_audio!(eng)
    end
    return screen
end

function save_player_conf(ctx)
    pl = ctx.eng.player
    save_setting!("player", player_settings(pl, ctx.eq[], ctx.gain_db[], ctx.sl[].name, ctx.midi_want[]))
end

"""
    player_midi_out!(ctx, name) -> message

Opens the MIDI output `name` for the player (`""` = off) after closing the open one, and keeps
the choice for the settings. Never throws; the message is for the status line.
"""
function player_midi_out!(ctx, name::AbstractString)
    eng = ctx.eng
    fail() = (ctx.midi_msg[] = L("MIDI-Ausgang „{1}“ lässt sich nicht öffnen.", name))
    try
        midi_out_close!(eng.player, eng.lock)
        ctx.midi_out[] = ""; ctx.midi_msg[] = ""
        ctx.midi_want[] = String(name)
        isempty(name) && return L("MIDI-Ausgang aus.")
        p = open_midi_out(name)
        p == C_NULL && return fail()
        eng.player.merr[] = 0
        eng.player.mout[] = UInt(p)                      # for the audio thread, now that it is open
        ctx.midi_out[] = String(name)
        return L("MIDI-Ausgang: {1}. MIDI-Dateien im Setup spielen über dieses Gerät.", name)
    catch e
        @warn "MIDI output" exception = e
        return fail()
    end
end

"State of a player window: setup, preparation progress, master values, MIDI output, screen."
player_context(eng::Engine; gain_db::Real = 0.0, eq = (0.0, 0.0, EQ_MIDF_DEFAULT, 0.0)) =
    (eng = eng, sl = Ref(Setlist()), ready = Ref(Bool[]), dur = Ref(Float64[]), err = Ref(String[]),
     gen = Ref(0), preparing = Ref(0), gain_db = Ref(Float64(gain_db)), eq = Ref(NTuple{4,Float64}(eq)),
     screen = Ref{Any}(nothing), tick = Ref{Function}(() -> nothing), editor = Ref{Any}(nothing),
     midi_out = Ref(""),              # open MIDI output
     midi_want = Ref(""),             # chosen MIDI output (saved, also while the device is missing)
     midi_outs = Ref(String[]),       # MIDI outputs found
     midi_msg = Ref(""))              # why the chosen output is not open (stays in the status line)

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
                                                    msg = Ref(""), on_saved = nothing, src = Ref(sl.name))), DM_THEME)
    return ctx, pfig, ptick!, efig
end

"Puts setup `sl` into the player and prepares its songs in a background thread."
function player_use!(ctx, sl::Setlist)
    eng = ctx.eng; pl = eng.player
    ctx.sl[] = sl
    n = length(sl.entries)
    # The generation goes up before the new setup is loaded, and the worker writes only into its
    # own arrays and checks the generation again under the lock: a render of the previous setup
    # that finishes now can no longer fill an entry of this one.
    gen = (ctx.gen[] += 1)
    ready = fill(false, n); dur = zeros(n); err = fill("", n)
    lock(() -> player_load!(pl, sl), eng.lock)
    ctx.ready[] = ready; ctx.dur[] = dur; ctx.err[] = err
    ctx.preparing[] = n
    Threads.@spawn for (i, e) in enumerate(sl.entries)
        ctx.gen[] == gen || return                       # another setup was loaded meanwhile
        try
            y, cue, m = prepare_entry_cue(e)
            ok = lock(eng.lock) do
                ctx.gen[] == gen || return false
                if i <= length(pl.items)
                    pl.items[i] = y; pl.cues[i] = cue
                    m === nothing || ((pl.mframe[i], pl.mmsg[i], pl.mchans[i]) = m)
                end
                true
            end
            ok || return
            dur[i] = size(y, 1) / SR
            ready[i] = true
        catch ex
            err[i] = sprint(showerror, ex)
        end
        ctx.gen[] == gen || return
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
    ismidi = [is_midi_file(e.path) for e in sl.entries]
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
    Label(mbox[12, 1], L("MIDI-Ausgang"), color = C_TEXT2, halign = :left)
    midi_off = L("aus")
    function out_opts(names)                          # off, the outputs found, the open one
        o = vcat([midi_off], names)
        isempty(ctx.midi_out[]) || ctx.midi_out[] in o || push!(o, ctx.midi_out[])
        return o
    end
    out_cur() = isempty(ctx.midi_out[]) ? midi_off : ctx.midi_out[]
    outmenu = Menu(mbox[12, 2:3], options = out_opts(ctx.midi_outs[]), default = out_cur(), width = 230)
    out_sync = Ref(false)                             # menu is being set from code
    function set_out_menu!()
        o = out_opts(ctx.midi_outs[])
        out_sync[] = true
        try
            o == outmenu.options[] || (outmenu.options[] = o)
            k = something(findfirst(==(out_cur()), o), 1)
            outmenu.i_selected[] == k || (outmenu.i_selected[] = k)
        finally
            out_sync[] = false
        end
    end
    on(outmenu.is_open) do open                       # devices may be plugged in meanwhile
        open || return
        ctx.midi_outs[] = midi_outputs()
        set_out_menu!()
    end
    on(outmenu.selection) do sel
        (sel === nothing || out_sync[]) && return
        name = sel == midi_off ? "" : sel
        name == ctx.midi_out[] && name == ctx.midi_want[] && return   # "aus" also forgets a missing device
        status[] = player_midi_out!(ctx, name)
        save_player_conf(ctx)
        set_out_menu!()
    end
    Label(mbox[13, 1:3], L("Auto: Setup läuft mit Pausen und Beeps durch, Klick auf einen Song startet ab dort.\nManuell: Klick spielt den Song sofort, ohne Pause und Beep.\nDie Effekte der Songs bleiben erhalten, der Master wirkt zusätzlich.\nBeep/Einzähler: Countdown-Beeps und Einzähler der Songs; auf „aus“ läuft der Countdown nur in der Statuszeile.\nAusgang „Musik links, Beep rechts“: links zur PA, rechts auf den Kopfhörer.\nMIDI-Ausgang: MIDI-Dateien im Setup spielen über dieses Gerät (USB), WAVs und Songs über die Soundkarte."),
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
        w !== nothing && isopen(w) && return raise_window!(w)
        ctx.editor[] = show_setlist_editor(copy_setlist(sl); on_saved = player_reload!)
    end

    # ---------------------------------------------------------------- display
    last = Ref{Any}(nothing)
    rt_note(rt) = "   ·   " * (rt > 0 ? L("Echtzeit-Priorität {1}", rt) : L("ohne Echtzeit-Priorität"))
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
            midi = get(ismidi, cur, false)
            merr = midi && pl.mout[] != 0 && pl.merr[] > 0          # writes fail: device unplugged?
            key = (st, cur, floor(Int, t), merr)
            if key != last[]
                status[] = "▶ $cur · $(get(titles, cur, ""))   $(fmt_time(t)) / $(fmt_time(get(ctx.dur[], cur, 0.0)))" *
                           (midi && pl.mout[] == 0 ? "   ·   " * L("MIDI-Datei, aber kein MIDI-Ausgang gewählt: läuft stumm") :
                            merr ? "   ·   " * L("MIDI-Ausgang „{1}“ antwortet nicht.", ctx.midi_out[]) : "")
            end
        else
            p = ctx.preparing[]
            rt = eng.rt[]
            mm = ctx.midi_msg[]
            key = (st, p, rt, mm)
            if key != last[]
                status[] = (p > 0 ? L("Bereite die Songs vor … noch {1}", p) :
                            isempty(sl.entries) ? L("Kein Setup geladen.") :
                            L("Bereit: {1} – {2}", sl.name, pl.auto ? L("Auto") : L("Manuell"))) * rt_note(rt) *
                           (isempty(mm) ? "" : "   ·   " * mm)
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
    keep_pause_beep!(sl, old) -> sl

Copies pause and beep from the entries of `old` to the entries of `sl` with the same path, in
order (a song that appears twice is matched first to first). Entries not in `old` stay as they are.
"""
function keep_pause_beep!(sl::Setlist, old::Setlist)
    pool = Dict{String,Vector{SetEntry}}()
    for e in old.entries
        push!(get!(pool, e.path, SetEntry[]), e)
    end
    for e in sl.entries
        q = get(pool, e.path, nothing)
        (q === nothing || isempty(q)) && continue
        o = popfirst!(q)
        e.pause = o.pause; e.beep = o.beep
    end
    return sl
end

"""
    keep_saved_pause_beep!(sl, src) -> sl

Before the setup editor saves `sl`: pause and beep are set in the player, which saves them at
once, so the editor's copy may be older. Takes them from the saved setup `src` (the one the
editor copy came from), or from the file of the target name `sl.name` if `src` has no file.
"""
function keep_saved_pause_beep!(sl::Setlist, src::AbstractString)
    for nm in (src, sl.name)
        isempty(nm) && continue
        p = setlist_path(nm)
        isfile(p) || continue
        old = try load_setlist(p) catch; nothing end
        old === nothing || keep_pause_beep!(sl, old)
        break
    end
    return sl
end

"""
    show_setlist_editor(sl = Setlist(); on_saved = nothing) -> screen

Opens the setup editor: add songs (.toml), audio files (.wav) or MIDI files (.mid), change the
order, save the setup.
`on_saved(sl)` is called after saving (the player then reloads the setup).
"""
function show_setlist_editor(sl::Setlist = Setlist(); on_saved = nothing)
    state = (sl = Ref(sl), screen = Ref{Any}(nothing), msg = Ref(""), on_saved = on_saved,
             src = Ref(sl.name))                # saved setup the editor copy came from
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
    filebtn = Button(add[1, 2], label = L("Dateien hinzufügen (TOML/WAV/MIDI) …"))
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
        keep_saved_pause_beep!(sl, state.src[])
        p = save_setlist(sl)
        state.src[] = sl.name
        state.msg[] = L("Gespeichert: {1}", p); status[] = state.msg[]
        state.on_saved === nothing || state.on_saved(copy_setlist(sl))
    end
    on(newbtn.clicks) do _
        state.sl[] = Setlist(); state.src[] = ""; state.msg[] = ""; editor_rebuild!(state)
    end
    on(loadmenu.selection) do s
        s in names || return
        state.sl[] = load_setlist(setlist_path(s)); state.src[] = s
        state.msg[] = L("Geladen: {1}", s); editor_rebuild!(state)
    end
    on(songmenu.selection) do s
        s in songs || return
        f = song_file(s); isfile(f) || return
        push!(sl.entries, SetEntry(f)); state.msg[] = L("Hinzugefügt: {1}", s); editor_rebuild!(state)
    end
    on(filebtn.clicks) do _
        @async begin
            paths = pick_files(song_dir(); title = L("Songs, WAV- oder MIDI-Dateien hinzufügen"),
                               exts = ("toml", "wav", "WAV", "mid", "MID", "midi", "MIDI"), kind = L("Songs, Audio und MIDI"))
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
    start_log!(what = "setup player")
    eng = Engine(Song(), synth_kit())                       # no GC pause: the player only plays finished audio
    start_audio!(eng; latency = max(audio_latency(), 0.15))   # no live input: a larger buffer is safer
    screen = show_player(eng; standalone = true)
    if block
        wait(screen)
        t0 = time()          # the window task saves the settings, closes the MIDI output, stops the audio
        while (PLAYER_CTX[] !== nothing || eng.task !== nothing) && time() - t0 < 5
            sleep(0.05)
        end
    end
    return screen
end
