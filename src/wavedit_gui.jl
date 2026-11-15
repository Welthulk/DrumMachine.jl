# WAV editor window ("WAV-Editor") in the style of the drum machine. Uses the editor core in
# wavedit.jl and plays through the drum machine's audio engine (`preview_play!`).

const WE_WAVE   = Makie.to_color("#e8771e")      # waveform
const WE_SEL    = Makie.to_color("#33547c")      # selection background
const WE_CURSOR = Makie.to_color("#ffd59e")      # edit cursor
const WE_PLAY   = Makie.to_color("#7fb2ff")      # playhead

const WE_BITS = [("16 Bit", 16), ("24 Bit", 24), ("32 Bit Float", 32), ("AAC (.m4a)", 0)]   # 0 = AAC via ffmpeg   # (German display key, bits)
const WE_EQF = [("250 Hz", 250), ("500 Hz", 500), ("800 Hz", 800), ("1.6 kHz", 1600), ("3.2 kHz", 3200)]

"Bit depth as shown to the user."
we_bits_label(b::Integer) = b == 32 ? L("32 Bit Float") : L("{1} Bit", b)

"Seconds as m:ss.mmm (or s.mmm below one minute)."
function fmt_secs(t::Real)
    t < 60 && return string(round(t, digits = 3), " s")
    m = floor(Int, t / 60)
    return string(m, ":", lpad(string(round(t - 60m, digits = 3)), 6, '0'))
end

"""
Character a key produces on the current keyboard layout. GLFW reports key codes by their US
position, so on a German QWERTZ keyboard the key labelled Z arrives as `Keyboard.y`; this asks GLFW
for the localized name. Falls back to the US letter when no window system is available (tests).
"""
function layout_char(k::Keyboard.Button)
    code = Int(k)
    us = Int(Keyboard.a) <= code <= Int(Keyboard.z) ? Char(code + 32) : '\0'
    try
        name = GLMakie.GLFW.GetKeyName(GLMakie.GLFW.Key(code), 0)
        (name isa AbstractString && length(name) == 1) && return lowercase(name[1])
    catch
    end
    return us
end

"""
    wave_editor_figure(eng; wave = nothing, last_export = Ref("")) -> (fig, tick!, load!)

Builds the editor window. `tick!()` must be called regularly (moves the playhead), `load!(path)`
opens a file. `last_export` points to the most recent WAV export of the drum machine.
"""
function wave_editor_figure(eng::Engine; wave::Union{Nothing,Wave} = nothing, last_export = Ref(""))
    fig = Figure(size = (1320, 960), backgroundcolor = C_BG, fontsize = 14, figure_padding = 18)
    status = Observable(L("Datei öffnen oder einen WAV-Export der Drum Machine laden.  Leertaste: Play/Stop · Maus ziehen: Auswahl · Mausrad: Zoom"))

    # ----------------------------------------------------------------- state
    w = Ref{Union{Nothing,Wave}}(wave)
    sel = Ref{Union{Nothing,UnitRange{Int}}}(nothing)   # selected frames
    cursor = Ref(1)                                      # edit/play position (frame)
    view = Ref((1, 1))                                   # visible frames (first, last)
    hist = History(30)
    clip = Ref{Union{Nothing,Tuple{Matrix{Float32},Int}}}(nothing)   # (frames, sample rate)
    updating = Ref(false)
    aac = Ref(false)                                     # format menu on AAC (export copies as .m4a)                                # widgets are being set from the state
    pending_discard = Ref("")                            # action waiting for a second click
    modified = Ref(false)
    last_dir = Ref(song_dir())

    # ----------------------------------------------------------------- header
    hdr = fig[1, 1] = GridLayout(tellwidth = false, halign = :left)
    Label(hdr[1, 1], L("WAV-EDITOR"), font = :bold, fontsize = 22, color = C_TEXT)
    file_lab = Label(hdr[1, 2], "", fontsize = 15, color = C_ACTIVE, padding = (14, 0, 0, 0))
    info_lab = Label(hdr[1, 3], "", fontsize = 13, color = C_TEXT2, padding = (14, 0, 0, 0))

    # ----------------------------------------------------------------- file + transport
    panel!(fig[2, 1])
    tbox = fig[2, 1] = GridLayout(tellwidth = false, halign = :left, alignmode = Outside(14))
    r1 = tbox[1, 1] = GridLayout(halign = :left)
    Label(r1[1, 1], L("DATEI"), font = :bold, color = C_TEXT2, width = 70, halign = :left)
    openbtn = Button(r1[1, 2], label = L("Öffnen …"))
    lastbtn = Button(r1[1, 3], label = L("Letzten Export öffnen"))
    savebtn = Button(r1[1, 4], label = L("Speichern"), width = 110)
    saveasbtn = Button(r1[1, 5], label = L("Speichern unter …"))
    selsavebtn = Button(r1[1, 6], label = L("Auswahl speichern …"))
    Label(r1[1, 7], "Format", halign = :right, color = C_TEXT2, padding = (14, 0, 0, 0))
    bits_opts = Ls(first.(WE_BITS))
    bits_menu = Menu(r1[1, 8], options = bits_opts, default = bits_opts[1], width = 120)
    Label(r1[1, 9], L("Kanäle"), halign = :right, color = C_TEXT2)
    chan_opts = Ls(["Mono", "Stereo"])
    chan_menu = Menu(r1[1, 10], options = chan_opts, default = chan_opts[2], width = 90)

    r2 = tbox[2, 1] = GridLayout(halign = :left)
    playbtn = Button(r2[1, 1], label = "▶  Play", width = 100, buttoncolor = C_ACTIVE, labelcolor = C_BG,
                     buttoncolor_hover = C_LEVEL_H[2], labelcolor_hover = C_BG, labelcolor_active = C_BG,
                     font = :bold)
    playselbtn = Button(r2[1, 2], label = L("Auswahl spielen"))
    Label(r2[1, 3], "Loop", halign = :right, color = C_TEXT2)
    loop_toggle = Toggle(r2[1, 4], active = false)
    Label(r2[1, 5], "  Zoom", halign = :right, color = C_TEXT2)
    zinbtn = Button(r2[1, 6], label = "+", width = 34)
    zoutbtn = Button(r2[1, 7], label = "−", width = 34)
    fitbtn = Button(r2[1, 8], label = L("Alles"))
    zselbtn = Button(r2[1, 9], label = L("Auswahl"))
    undobtn = Button(r2[1, 10], label = L("↶ Rückgängig"))
    redobtn = Button(r2[1, 11], label = L("↷ Wiederholen"))
    pos_lab = Label(r2[1, 12], "", color = C_TEXT2, fontsize = 13, padding = (14, 0, 0, 0))
    rowgap!(tbox, 10)

    # ----------------------------------------------------------------- waveform
    panel!(fig[3, 1])
    wbox = fig[3, 1] = GridLayout(tellwidth = false, alignmode = Outside(14))
    ax = Axis(wbox[1, 1], backgroundcolor = C_OFF_B, height = 360,
              xgridcolor = C_LINE, ygridvisible = false, yticksvisible = false, yticklabelsvisible = false,
              xticklabelcolor = C_TEXT2, xtickcolor = C_LINE, bottomspinecolor = C_LINE,
              topspinevisible = false, leftspinevisible = false, rightspinevisible = false,
              xlabel = L("Sekunden"), xlabelcolor = C_TEXT2, xlabelsize = 12)
    for k in (:rectanglezoom, :scrollzoom, :dragpan, :limitreset)
        try deregister_interaction!(ax, k) catch end
    end
    selrect = Observable(Rect2f(0, 0, 0, 0))
    poly!(ax, selrect; color = (WE_SEL, 0.85), strokewidth = 0)
    segs = Observable(Point2f[])
    linesegments!(ax, segs; color = WE_WAVE, linewidth = 1)
    centers = Observable(Point2f[])
    linesegments!(ax, centers; color = C_LINE, linewidth = 1)
    curx = Observable([0.0]); playx = Observable([NaN])
    vlines!(ax, curx; color = WE_CURSOR, linewidth = 1.5)
    vlines!(ax, playx; color = WE_PLAY, linewidth = 2)
    scroll = Slider(wbox[2, 1], range = 0:0.0001:1, startvalue = 0)

    # ----------------------------------------------------------------- edit panel
    panel!(fig[4, 1])
    ebox = fig[4, 1] = GridLayout(tellwidth = false, halign = :left, alignmode = Outside(14))
    e1 = ebox[1, 1] = GridLayout(halign = :left)
    Label(e1[1, 1], L("BEARBEITEN"), font = :bold, color = C_TEXT2, width = 110, halign = :left)
    cutbtn = Button(e1[1, 2], label = L("Ausschneiden"))
    copybtn = Button(e1[1, 3], label = L("Kopieren"))
    pastebtn = Button(e1[1, 4], label = L("Einfügen"))
    delbtn = Button(e1[1, 5], label = L("Löschen"))
    cropbtn = Button(e1[1, 6], label = L("Zuschneiden"))
    silbtn = Button(e1[1, 7], label = L("Stille"))
    revbtn = Button(e1[1, 8], label = L("Umkehren"))
    e2 = ebox[2, 1] = GridLayout(halign = :left)
    Label(e2[1, 1], L("PEGEL"), font = :bold, color = C_TEXT2, width = 110, halign = :left)
    fadeinbtn = Button(e2[1, 2], label = "Fade in")
    fadeoutbtn = Button(e2[1, 3], label = "Fade out")
    curve_opts = Ls(["linear", "weich"])
    curve_menu = Menu(e2[1, 4], options = curve_opts, default = curve_opts[2], width = 90)
    normbtn = Button(e2[1, 5], label = L("Normalisieren"))
    Label(e2[1, 6], L("auf"), color = C_TEXT2)
    norm_menu = Menu(e2[1, 7], options = ["0 dB", "-0.1 dB", "-1 dB", "-3 dB", "-6 dB"], default = "-0.1 dB", width = 90)
    Label(e2[1, 8], "  Gain", halign = :right, color = C_TEXT2)
    gain_sl = Slider(e2[1, 9], range = -24:0.5:24, startvalue = 0, width = 160)
    gain_lab = Label(e2[1, 10], "0 dB", width = 56, color = C_TEXT)
    gainbtn = Button(e2[1, 11], label = L("Gain anwenden"))
    e3 = ebox[3, 1] = GridLayout(halign = :left)
    Label(e3[1, 1], L("EFFEKT"), font = :bold, color = C_TEXT2, width = 110, halign = :left)
    fx_menu = Menu(e3[1, 2], options = filter(!=("EQ"), WAVE_FX), default = "Room", width = 110)
    Label(e3[1, 3], "Mix", color = C_TEXT2)
    fxmix_sl = Slider(e3[1, 4], range = 0:0.01:1, startvalue = 0.4, width = 140)
    fxmix_lab = Label(e3[1, 5], "", width = 44, color = C_TEXT)
    fxbtn = Button(e3[1, 6], label = L("Effekt anwenden"))
    Label(e3[1, 7], "   " * L("Hall und Echo klingen über das Dateiende hinaus aus, die Datei wird dann länger."),
          color = C_DIM, fontsize = 12)
    e5 = ebox[4, 1] = GridLayout(halign = :left)
    Label(e5[1, 1], "EQ", font = :bold, color = C_TEXT2, width = 110, halign = :left)
    Label(e5[1, 2], L("Tiefen"), color = C_TEXT2)
    eql_sl = Slider(e5[1, 3], range = -12:0.5:12, startvalue = 0, width = 110)
    Label(e5[1, 4], L("Mitten"), color = C_TEXT2)
    eqm_sl = Slider(e5[1, 5], range = -12:0.5:12, startvalue = 0, width = 110)
    Label(e5[1, 6], L("bei"), color = C_TEXT2)
    eqf_opts = Ls(first.(WE_EQF))
    eqf_menu = Menu(e5[1, 7], options = eqf_opts, default = eqf_opts[3], width = 90)
    Label(e5[1, 8], L("Höhen"), color = C_TEXT2)
    eqh_sl = Slider(e5[1, 9], range = -12:0.5:12, startvalue = 0, width = 110)
    eq_lab = Label(e5[1, 10], "", color = C_TEXT, fontsize = 12, width = 130)
    eqbtn = Button(e5[1, 11], label = L("EQ anwenden"))
    e4 = ebox[5, 1] = GridLayout(halign = :left)
    Label(e4[1, 1], "INTRO", font = :bold, color = C_TEXT2, width = 110, halign = :left)
    Label(e4[1, 2], L("Stille"), color = C_TEXT2)
    silsec_tb = Textbox(e4[1, 3], stored_string = "0.5", validator = Float64, width = 60, reset_on_defocus = false)
    Label(e4[1, 4], "s", color = C_TEXT2)
    insilbtn = Button(e4[1, 5], label = L("am Cursor einfügen"))
    Label(e4[1, 6], "   " * L("Einzähler"), color = C_TEXT2)
    bpm_tb = Textbox(e4[1, 7], stored_string = string(round(Int, eng.song.bpm)), validator = Int, width = 60,
                     reset_on_defocus = false)
    Label(e4[1, 8], "BPM", color = C_TEXT2)
    beats_menu = Menu(e4[1, 9], options = string.(1:8), default = "4", width = 60)
    Label(e4[1, 10], L("Schläge"), color = C_TEXT2)
    countinbtn = Button(e4[1, 11], label = L("voranstellen"))
    bpmbtn = Button(e4[1, 12], label = L("BPM erkennen"))
    rowgap!(ebox, 8)

    Label(fig[5, 1], status, halign = :left, tellwidth = false, color = C_TEXT2, fontsize = 13)
    rowgap!(fig.layout, 12)
    colsize!(fig.layout, 1, Relative(1))

    # ----------------------------------------------------------------- helpers
    have() = w[] !== nothing && nframes(w[]) > 0
    nf() = have() ? nframes(w[]) : 1
    secs(i) = have() ? (i - 1) / w[].fs : 0.0
    frame_at(t) = have() ? clamp(round(Int, t * w[].fs) + 1, 1, nf() + 1) : 1   # nf()+1 = after the end
    playfrom() = clamp(cursor[], 1, nf())
    # range edits work on the selection, or on the whole file
    work_range() = sel[] === nothing ? (1:nf()) : sel[]
    playing() = eng.preview.on

    function redraw!()
        if !have()
            segs[] = Point2f[]; centers[] = Point2f[]; selrect[] = Rect2f(0, 0, 0, 0)
            limits!(ax, 0, 1, -1.1, 1.1)
            return
        end
        wv = w[]; a, b = view[]
        nc = nchan(wv)
        ys = nc == 1 ? [0.0] : [1.05, -1.05]                 # channel centers
        px = max(200, round(Int, ax.scene.viewport[].widths[1]))
        pts = Point2f[]
        for (c, y0) in enumerate(ys[1:min(nc, 2)])
            mn, mx = wave_peaks(wv, c, a, b, px)
            n = length(mn); span = b - a + 1
            for k in 1:n
                t = secs(a + (k - 0.5) * span / n)
                push!(pts, Point2f(t, y0 + mn[k]), Point2f(t, y0 + max(mx[k], mn[k] + 1f-3)))
            end
        end
        segs[] = pts
        t0, t1 = secs(a), secs(b + 1)
        centers[] = vcat(([Point2f(t0, y), Point2f(t1, y)] for y in ys)...)
        ylo, yhi = nc == 1 ? (-1.1, 1.1) : (-2.2, 2.2)
        limits!(ax, t0, t1, ylo, yhi)
        if sel[] === nothing
            selrect[] = Rect2f(0, 0, 0, 0)
        else
            s0, s1 = secs(first(sel[])), secs(last(sel[]) + 1)
            selrect[] = Rect2f(s0, ylo, s1 - s0, yhi - ylo)
        end
        curx[] = [secs(cursor[])]
        span = nf() - (b - a + 1)
        updating[] = true
        try
            set_close_to!(scroll, span <= 0 ? 0.0 : (a - 1) / span)
        finally
            updating[] = false
        end
    end

    function refresh_info!()
        if !have()
            file_lab.text[] = L("keine Datei"); info_lab.text[] = ""; pos_lab.text[] = ""
            return
        end
        wv = w[]
        file_lab.text[] = (isempty(wv.path) ? L("unbenannt") * ".wav" : basename(wv.path)) * (modified[] ? "  •" : "")
        nc = nchan(wv)
        chans = nc == 1 ? L("Mono") : nc == 2 ? L("Stereo") : L("{1} Kanäle", nc)
        info_lab.text[] = "$(wv.fs) Hz · $chans · $(we_bits_label(wv.bits)) · $(fmt_secs(duration(wv)))"
        st = "Cursor $(fmt_secs(secs(cursor[])))"
        if sel[] !== nothing
            st *= "   " * L("Auswahl {1} – {2}  ({3})", fmt_secs(secs(first(sel[]))), fmt_secs(secs(last(sel[]) + 1)),
                             fmt_secs(length(sel[]) / wv.fs))
        end
        pos_lab.text[] = st
        undobtn.label[] = isempty(hist.undo) ? L("↶ Rückgängig") : L("↶ Rückgängig ({1})", length(hist.undo))
        redobtn.label[] = isempty(hist.redo) ? L("↷ Wiederholen") : L("↷ Wiederholen ({1})", length(hist.redo))
        updating[] = true
        try
            bits_menu.i_selected[] = aac[] ? length(WE_BITS) : something(findfirst(o -> o[2] == wv.bits, WE_BITS), 1)
            chan_menu.i_selected[] = nchan(wv) == 1 ? 1 : 2
        finally
            updating[] = false
        end
    end
    refresh!() = (redraw!(); refresh_info!())

    function set_view!(a, b)
        n = nf(); len = clamp(b - a + 1, min(n, 32), n)
        a = clamp(a, 1, n - len + 1)
        view[] = (a, a + len - 1)
        redraw!()
    end
    fit!() = set_view!(1, nf())
    function zoom!(f, center = nothing)
        have() || return
        a, b = view[]; len = b - a + 1
        c = something(center, cursor[])
        nlen = round(Int, len * f)
        set_view!(c - round(Int, (c - a) * nlen / len), c - round(Int, (c - a) * nlen / len) + nlen - 1)
    end

    function stop_play!()
        preview_stop!(eng); playx[] = [NaN]; playbtn.label[] = "▶  Play"
    end

    # Unsaved edits: the first click on a discarding action only warns, the second one proceeds.
    function confirm_discard!(action::AbstractString)
        (!have() || !modified[] || pending_discard[] == action) && (pending_discard[] = ""; return true)
        pending_discard[] = action
        status[] = L("Ungespeicherte Änderungen! Nochmal „{1}“ klicken zum Verwerfen, oder erst speichern.", action)
        return false
    end

    function load!(path::AbstractString)
        try
            stop_play!()
            nch = WAV.wavread(path; format = "size")[2]
            w[] = load_wave(path)
            last_dir[] = dirname(path)
            empty!(hist.undo); empty!(hist.redo)
            sel[] = nothing; cursor[] = 1; modified[] = false
            fit!(); refresh_info!()
            status[] = L("Geladen: {1}", path) * (nch > 2 ? "  " * L("(Datei hat {1} Kanäle – die ersten beiden werden bearbeitet)", nch) : "")
        catch e
            status[] = L("Fehler beim Laden: {1}", sprint(showerror, e))
        end
    end

    # Runs edit `f(wave, range)` with undo. The state before the edit is kept only if the edit
    # succeeds, so a failing edit leaves no empty undo step (SEdit stored it first).
    # `label` is already translated (it is stored in the undo history and shown as is).
    function edit!(label::AbstractString, f; needsel::Bool = false, after = nothing, ranged::Bool = true)
        have() || (status[] = L("Keine Datei geladen."); return false)
        needsel && sel[] === nothing && (status[] = L("{1}: erst einen Bereich auswählen (Maus ziehen).", label); return false)
        r = work_range(); hadsel = sel[] !== nothing
        before = copy(w[].data)
        pending_discard[] = ""
        try
            playing() && stop_play!()
            f(w[], r)
            nframes(w[]) == 0 && error(L("Die Datei darf nicht leer werden – zum Neuanfang eine andere Datei öffnen"))
        catch e
            w[].data = before
            status[] = "$label: $(e isa ErrorException ? e.msg : sprint(showerror, e))"
            return false
        end
        push!(hist.undo, (before, String(label)))
        length(hist.undo) > hist.limit && popfirst!(hist.undo)
        empty!(hist.redo)
        modified[] = true
        after === nothing ? (sel[] !== nothing && last(sel[]) > nf() && (sel[] = nothing)) : after(r)
        cursor[] = clamp(cursor[], 1, nf() + 1)
        a, b = view[]
        b > nf() || b - a + 1 < 32 ? fit!() : redraw!()
        refresh_info!()
        status[] = label * (ranged && !hadsel && !needsel ? " " * L("(ganze Datei)") : "") * "."
        return true
    end

    # ----------------------------------------------------------------- mouse on the waveform
    anchor = Ref(0)
    register_interaction!(ax, :waveedit) do ev::MouseEvent, _
        have() || return Consume(false)
        f = frame_at(ev.data[1])
        shift = Keyboard.left_shift in events(fig).keyboardstate || Keyboard.right_shift in events(fig).keyboardstate
        if ev.type == MouseEventTypes.leftdown
            if shift
                a, b = sel[] === nothing ? (cursor[], cursor[]) : (first(sel[]), last(sel[]))
                sel[] = min(a, f):max(b, f)
            else
                anchor[] = f; cursor[] = f; sel[] = nothing
                playing() && preview_play!(eng, w[].data, w[].fs; from = min(f, nf()), loop = loop_toggle.active[])
            end
        elseif ev.type in (MouseEventTypes.leftdrag, MouseEventTypes.leftdragstart)
            anchor[] > 0 && (sel[] = min(anchor[], f):min(max(anchor[], f), nf()); cursor[] = first(sel[]))
        elseif ev.type == MouseEventTypes.leftup
            sel[] !== nothing && length(sel[]) < 2 && (sel[] = nothing)
        else
            return Consume(false)
        end
        redraw!(); refresh_info!()
        return Consume(true)
    end
    register_interaction!(ax, :wavezoom) do ev::ScrollEvent, _
        have() || return Consume(false)
        mp = mouseposition(ax.scene)
        zoom!(ev.y > 0 ? 0.8 : 1.25, frame_at(mp[1]))
        return Consume(true)
    end
    on(scroll.value) do v
        (have() && !updating[]) || return
        a, b = view[]; len = b - a + 1; span = nf() - len
        span <= 0 && return
        na = round(Int, v * span) + 1
        na == a || (view[] = (na, na + len - 1); redraw!())
    end

    # ----------------------------------------------------------------- transport
    function play!(; selection = false)
        have() || return
        if playing() && !selection
            stop_play!(); return
        end
        wv = w[]
        if selection
            sel[] === nothing && (status[] = L("Keine Auswahl."); return)
            a, b = first(sel[]), last(sel[])
        else
            a = sel[] === nothing ? playfrom() : first(sel[])
            b = sel[] === nothing ? nf() : last(sel[])
        end
        preview_play!(eng, wv.data, wv.fs; from = a, to = b, loop = loop_toggle.active[])
        playbtn.label[] = "■  Stop"
    end
    on(_ -> play!(), playbtn.clicks)
    on(_ -> play!(selection = true), playselbtn.clicks)
    on(_ -> zoom!(0.5), zinbtn.clicks)
    on(_ -> zoom!(2.0), zoutbtn.clicks)
    on(_ -> fit!(), fitbtn.clicks)
    on(zselbtn.clicks) do _
        sel[] === nothing ? fit!() : set_view!(first(sel[]) - length(sel[]) ÷ 20, last(sel[]) + length(sel[]) ÷ 20)
    end

    # ----------------------------------------------------------------- undo
    function undo_redo!(redo::Bool)
        have() || return
        stop_play!()
        label = redo ? redo!(hist, w[]) : undo!(hist, w[])
        label === nothing && (status[] = redo ? L("Nichts wiederherzustellen.") : L("Nichts rückgängig zu machen."); return)
        modified[] = true; sel[] = nothing; cursor[] = clamp(cursor[], 1, nf() + 1); pending_discard[] = ""
        a, b = view[]; b > nf() ? fit!() : redraw!(); refresh_info!()
        status[] = redo ? L("Wiederhergestellt: {1}", label) : L("Rückgängig: {1}", label)
    end
    on(_ -> undo_redo!(false), undobtn.clicks)
    on(_ -> undo_redo!(true), redobtn.clicks)

    # ----------------------------------------------------------------- edit actions
    curve() = findfirst(==(curve_menu.selection[]), curve_opts) == 1 ? :linear : :sine
    function do_copy!(; cut = false)
        have() || return
        sel[] === nothing && (status[] = L("Kopieren: erst einen Bereich auswählen."); return)
        clip[] = (copy_range(w[], sel[]), w[].fs)
        if cut
            a = first(sel[])
            edit!(L("Ausschneiden"), (wv, r) -> delete_range!(wv, r); needsel = true,
                  after = r -> (sel[] = nothing; cursor[] = a))
        else
            status[] = L("Kopiert: {1}", fmt_secs(size(clip[][1], 1) / clip[][2]))
        end
    end
    function do_paste!()
        clip[] === nothing && (status[] = L("Zwischenablage ist leer."); return)
        have() || (status[] = L("Keine Datei geladen."); return)
        at = sel[] === nothing ? cursor[] : first(sel[])
        data, cfs = clip[]
        n = round(Int, size(data, 1) * w[].fs / cfs)
        edit!(cfs == w[].fs ? L("Einfügen") : L("Einfügen (von {1} Hz umgerechnet)", cfs), (wv, _) -> paste!(wv, at, data; fs = cfs);
              ranged = false, after = _ -> (sel[] = at:min(at+n-1, nf()); cursor[] = at))
    end
    on(_ -> do_copy!(cut = true), cutbtn.clicks)
    on(_ -> do_copy!(), copybtn.clicks)
    on(_ -> do_paste!(), pastebtn.clicks)
    function do_delete!()
        a = sel[] === nothing ? 1 : first(sel[])
        edit!(L("Löschen"), delete_range!; needsel = true, after = _ -> (sel[] = nothing; cursor[] = clamp(a, 1, nf())))
    end
    on(_ -> do_delete!(), delbtn.clicks)
    on(cropbtn.clicks) do _
        edit!(L("Zuschneiden"), crop!; needsel = true, after = _ -> (sel[] = nothing; cursor[] = 1))
    end
    on(_ -> edit!(L("Stille"), silence!; needsel = true), silbtn.clicks)
    on(_ -> edit!(L("Umkehren"), reverse!), revbtn.clicks)
    on(_ -> edit!("Fade in", (wv, r) -> fade_in!(wv, r; curve = curve())), fadeinbtn.clicks)
    on(_ -> edit!("Fade out", (wv, r) -> fade_out!(wv, r; curve = curve())), fadeoutbtn.clicks)
    on(normbtn.clicks) do _
        db = parse(Float64, replace(norm_menu.selection[], " dB" => ""))
        edit!(L("Normalisieren auf {1}", norm_menu.selection[]), (wv, r) -> normalize!(wv, r; peak_db = db))
    end
    on(v -> (gain_lab.text[] = "$(v > 0 ? "+" : "")$(v) dB"), gain_sl.value; update = true)
    on(gainbtn.clicks) do _
        v = gain_sl.value[]
        v == 0 && (status[] = L("Gain ist 0 dB – nichts zu tun."); return)
        edit!("Gain $(v > 0 ? "+" : "")$(v) dB", (wv, r) -> gain!(wv, r, v))
    end
    eqfreq() = WE_EQF[something(findfirst(==(eqf_menu.selection[]), eqf_opts), 3)][2]
    on(v -> (fxmix_lab.text[] = "$(round(Int, 100v)) %"), fxmix_sl.value; update = true)
    for s in (eql_sl, eqm_sl, eqh_sl)
        on(_ -> (eq_lab.text[] = "$(eql_sl.value[]) / $(eqm_sl.value[]) / $(eqh_sl.value[]) dB"), s.value; update = true)
    end
    function run_fx!(fx)
        fx == "EQ" && all(iszero, (eql_sl.value[], eqm_sl.value[], eqh_sl.value[])) &&
            (status[] = L("EQ: alle Regler auf 0 dB – nichts zu tun."); return)
        bpm = something(tryparse(Int, something(bpm_tb.displayed_string[], "")), round(Int, eng.song.bpm))
        bpm > 0 || (bpm = round(Int, eng.song.bpm))
        edit!(fx == "EQ" ? "EQ $(eq_lab.text[])" : L("Effekt {1}", fx),
              (wv, r) -> apply_fx!(wv, r, fx; mix = fxmix_sl.value[], bpm = bpm,
                                   eq = (eql_sl.value[], eqm_sl.value[], eqfreq(), eqh_sl.value[])))
    end
    on(_ -> run_fx!(fx_menu.selection[]), fxbtn.clicks)
    on(_ -> run_fx!("EQ"), eqbtn.clicks)
    on(insilbtn.clicks) do _
        secs_ = something(tryparse(Float64, something(silsec_tb.displayed_string[], "")), 0.0)
        secs_ <= 0 && (status[] = L("Stille: Dauer in Sekunden eingeben."); return)
        at = cursor[]
        edit!(L("Stille {1} s eingefügt", secs_), (wv, _) -> insert_silence!(wv, at, secs_); ranged = false,
              after = _ -> (sel[] = at:at+round(Int, secs_ * w[].fs)-1))
    end
    on(countinbtn.clicks) do _
        bpm = tryparse(Int, something(bpm_tb.displayed_string[], ""))
        (bpm === nothing || bpm <= 0) && (status[] = L("Einzähler: BPM eingeben."); return)
        beats = parse(Int, beats_menu.selection[])
        edit!(L("Einzähler {1} × bei {2} BPM", beats, bpm), (wv, _) -> prepend_countin!(wv; bpm = bpm, beats = beats); ranged = false,
              after = _ -> (sel[] = nothing; cursor[] = 1))
    end
    on(bpmbtn.clicks) do _
        have() || return
        wv = w[]; r = work_range()
        b = estimate_bpm(Wave(wv.data[r, :], wv.fs))
        if b === nothing
            status[] = L("BPM nicht erkannt – bitte von Hand eingeben.")
        else
            bpm_tb.stored_string[] = string(b); bpm_tb.displayed_string[] = string(b)
            status[] = L("Erkannt: etwa {1} BPM (Takt = {2}).", b, fmt_secs(4 * 60 / b))
        end
    end

    # ----------------------------------------------------------------- format / channels
    on(bits_menu.selection) do s
        (s === nothing || !have() || updating[]) && return
        i = findfirst(==(s), bits_opts)
        i === nothing && return
        b = WE_BITS[i][2]
        if b == 0                              # AAC: export copy for messengers, the WAV stays as it is
            if !has_ffmpeg()
                status[] = L("AAC braucht das Programm ffmpeg (z. B. sudo apt install ffmpeg).")
                refresh_info!(); return
            end
            aac[] = true; refresh_info!()
            status[] = L("Format AAC: „Speichern“ schreibt eine .m4a neben die WAV (z. B. für WhatsApp). Die WAV bleibt unverändert.")
            return
        end
        aac[] = false
        b == w[].bits && (refresh_info!(); return)
        w[].bits = b; modified[] = true; refresh_info!()
        status[] = L("Speicherformat: {1}", s)
    end
    on(chan_menu.selection) do s
        (s === nothing || !have() || updating[]) && return
        n = findfirst(==(s), chan_opts) == 1 ? 1 : 2
        n == nchan(w[]) && return
        edit!(n == 1 ? L("In Mono umgewandelt") : L("In Stereo umgewandelt"), (wv, _) -> set_channels!(wv, n); ranged = false)
    end

    # ----------------------------------------------------------------- files (dialogs run async)
    busy = Ref(false)
    function dialog!(f)
        busy[] && return
        busy[] = true
        @async try
            f()
        catch e
            status[] = L("Fehler: {1}", sprint(showerror, e))
        finally
            busy[] = false
        end
    end
    no_dialog() = (status[] = L("Kein Datei-Dialog gefunden – bitte zenity oder kdialog installieren."))
    on(openbtn.clicks) do _
        confirm_discard!(L("Öffnen …")) || return
        dialog!() do
            p = pick_file(last_dir[]; title = L("WAV öffnen"), ext = "wav", kind = L("WAV-Dateien"))
            p === nothing ? no_dialog() : p == "" ? (status[] = L("Öffnen abgebrochen.")) : load!(p)
        end
    end
    on(lastbtn.clicks) do _
        isfile(last_export[]) || return (status[] = L("In dieser Sitzung wurde noch keine WAV exportiert."))
        confirm_discard!(L("Letzten Export öffnen")) && load!(last_export[])
    end
    function save_to!(p; range = nothing)
        wv = w[]
        if aac[]
            p = splitext(p)[1] * ".m4a"
            save_aac(p, wv; range)
            status[] = L("AAC gespeichert: {1} – die WAV ist unverändert.", p)
            return
        end
        save_wave(p, wv; range = range)
        if range === nothing
            wv.path = p; modified[] = false; refresh_info!()
        end
        warn = td27_name_warning(p)
        status[] = L("Gespeichert: {1} ({2})", p, we_bits_label(wv.bits)) * (warn == "" ? "" : "  ⚠ TD-27: $warn")
    end
    function save_as!(; range = nothing)
        have() || return
        dialog!() do
            base = isempty(w[].path) ? L("unbenannt") : splitext(basename(w[].path))[1]
            ext = aac[] ? "m4a" : "wav"
            name = (range === nothing ? base : base * " " * L("Ausschnitt")) * "." * ext
            p = pick_file(isempty(w[].path) ? last_dir[] : dirname(w[].path);
                          title = aac[] ? L("AAC speichern") : L("WAV speichern"), ext = ext,
                          kind = aac[] ? L("AAC-Dateien") : L("WAV-Dateien"), save = true, name = name)
            p === nothing && return no_dialog()
            p == "" && return (status[] = L("Speichern abgebrochen."))
            endswith(lowercase(p), "." * ext) || (p *= "." * ext)
            last_dir[] = dirname(p)
            save_to!(p; range = range)
        end
    end
    on(savebtn.clicks) do _
        have() || return
        isempty(w[].path) ? save_as!() : dialog!(() -> save_to!(w[].path))   # async: ffmpeg may take a moment
    end
    on(_ -> save_as!(), saveasbtn.clicks)
    on(_ -> (sel[] === nothing ? (status[] = L("Erst einen Bereich auswählen.")) : save_as!(range = sel[])), selsavebtn.clicks)

    # ----------------------------------------------------------------- keyboard
    on(events(fig).keyboardbutton) do ev
        ev.action in (Keyboard.press, Keyboard.repeat) || return
        any(tb -> tb.focused[], (silsec_tb, bpm_tb)) && return
        ks = events(fig).keyboardstate
        ctrl = Keyboard.left_control in ks || Keyboard.right_control in ks
        k = ev.key
        ch = layout_char(k)                    # letter on the user's keyboard layout (QWERTZ!)
        if k == Keyboard.space
            play!()
        elseif ctrl && ch == 'z'
            undo_redo!(false)
        elseif ctrl && ch == 'y'
            undo_redo!(true)
        elseif ctrl && ch == 'c'
            do_copy!()
        elseif ctrl && ch == 'x'
            do_copy!(cut = true)
        elseif ctrl && ch == 'v'
            do_paste!()
        elseif ctrl && ch == 'a'
            have() && (sel[] = 1:nf(); redraw!(); refresh_info!())
        elseif ctrl && ch == 's'
            notify(savebtn.clicks)
        elseif k == Keyboard.delete
            do_delete!()
        elseif k == Keyboard.escape
            sel[] = nothing; redraw!(); refresh_info!()
        elseif k == Keyboard.home
            cursor[] = 1; set_view!(1, view[][2] - view[][1] + 1); refresh_info!()
        elseif k == Keyboard._end
            cursor[] = nf() + 1; a, b = view[]; set_view!(nf() - (b - a), nf()); refresh_info!()
        else
            return
        end
        return Consume(true)
    end

    # ----------------------------------------------------------------- playhead
    # moves the playhead; when it leaves the visible range the view pages along
    function tick!()
        p = eng.preview
        if p.on && have() && p.data === w[].data
            f = p.shown[]
            f <= 0 && return
            playx[] = [secs(f)]
            a, b = view[]
            if f > b || f < a
                len = b - a + 1
                set_view!(f - len ÷ 5, f - len ÷ 5 + len - 1)
            end
        elseif !isnan(playx[][1])
            playx[] = [NaN]; playbtn.label[] = "▶  Play"
        end
        return
    end

    have() && (fit!(); refresh_info!())
    refresh!()
    return fig, tick!, load!
end

"""
    show_wave_editor(eng; path = "", last_export = Ref("")) -> (screen, load!)

Opens the WAV editor in its own window. `path` is loaded right away if given.
"""
function show_wave_editor(eng::Engine; path::AbstractString = "", last_export = Ref(""))
    fig, tick!, load! = with_theme(() -> wave_editor_figure(eng; last_export), DM_THEME)
    screen = display(GLMakie.Screen(; title = L("DrumMachine – WAV-Editor")), fig)
    set_icon!(screen)
    isempty(path) || load!(path)
    @async begin
        while isopen(screen)
            tick!()
            sleep(1 / 30)
        end
        preview_stop!(eng)
    end
    return screen, load!
end
