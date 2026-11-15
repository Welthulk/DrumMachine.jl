# GLMakie-Oberfläche: Step-Raster, Transport, Patterns/Kette, Speichern/Laden, WAV-Export.

using GLMakie

const SONG_DIR = normpath(joinpath(@__DIR__, "..", "songs"))

# Farbpalette (dunkel)
const C_BG      = Makie.to_color("#121418")     # Fensterhintergrund
const C_PANEL   = Makie.to_color("#1b1e24")     # Panels
const C_LINE    = Makie.to_color("#2c313a")     # Panel-Rahmen, Trennlinien
const C_TEXT    = Makie.to_color("#e3e6eb")
const C_TEXT2   = Makie.to_color("#8c94a0")     # Nebentext
const C_DIM     = Makie.to_color("#4a505b")     # inaktive Beschriftung
const C_OFF_A   = Makie.to_color("#2b3038")     # Step aus, Schlag 1/3/…
const C_OFF_B   = Makie.to_color("#23272e")     # Step aus, Schlag 2/4/…
const C_HEAD    = Makie.to_color("#33547c")     # Playhead auf leerem Step
const C_LEVEL   = (Makie.to_color("#8a5126"), Makie.to_color("#e8771e"), Makie.to_color("#ffb763"))
const C_LEVEL_H = (Makie.to_color("#b06a33"), Makie.to_color("#ff9640"), Makie.to_color("#ffd59e"))
const C_BTN     = Makie.to_color("#272b33")
const C_BTN_H   = Makie.to_color("#323843")
const C_BTN_A   = Makie.to_color("#3d4450")
const C_INPUT   = Makie.to_color("#16191e")
const C_ACTIVE  = Makie.to_color("#e8771e")
const C_ACT_DIM = Makie.to_color("#9c5418")
const C_MUTE    = Makie.to_color("#c9483f")
const C_SOLO    = Makie.to_color("#d4ad2a")

const DM_THEME = Theme(
    fontsize = 14, textcolor = C_TEXT, backgroundcolor = C_BG,
    Label = (color = C_TEXT,),
    Button = (buttoncolor = C_BTN, buttoncolor_hover = C_BTN_H, buttoncolor_active = C_BTN_A,
              labelcolor = C_TEXT, labelcolor_hover = C_TEXT, labelcolor_active = C_TEXT,
              strokewidth = 0, cornerradius = 6),
    Slider = (color_active = C_ACTIVE, color_active_dimmed = C_ACT_DIM, color_inactive = C_OFF_A),
    Toggle = (framecolor_inactive = C_OFF_A, framecolor_active = C_ACTIVE, buttoncolor = C_TEXT),
    Menu = (cell_color_inactive_even = C_BTN, cell_color_inactive_odd = C_BTN, cell_color_hover = C_BTN_H,
            cell_color_active = C_ACT_DIM, selection_cell_color_inactive = C_BTN, textcolor = C_TEXT,
            dropdown_arrow_color = C_TEXT2),
    Textbox = (boxcolor = C_INPUT, boxcolor_hover = C_INPUT, boxcolor_focused = C_INPUT,
               bordercolor = C_LINE, bordercolor_hover = C_DIM, bordercolor_focused = C_ACTIVE,
               textcolor = C_TEXT, textcolor_placeholder = C_DIM, cursorcolor = C_ACTIVE),
)

"Setzt einen Toggle nur, wenn sich der Wert ändert (sonst kippt die Anzeige)."
set_toggle!(t, v::Bool) = (t.active[] == v || (t.active[] = v); t)

"Hintergrund-Panel für eine Zeile des Hauptlayouts."
panel!(pos) = Box(pos, color = C_PANEL, strokecolor = C_LINE, strokewidth = 1, cornerradius = 10,
                  tellwidth = false, tellheight = false)

const HELP_TEXT = """
EINGABE
  Linksklick            Schlag an / aus
  Rechtsklick           Ghost  →  normal  →  Akzent
  Spurname              Vorhören      M / S   Stumm / Solo (gilt auch für den Export)
  Spur-Effekte          Spurname anklicken: EQ (Tiefen, Mitten, Höhen) und
                        Chorus / Flanger für diese Spur, wird im Song gespeichert

TRANSPORT
  Leertaste             Play / Stop
  Modus Pattern         spielt das angezeigte Pattern in Schleife
  Modus Song            spielt die Kette in Schleife, das Raster zeigt das laufende Pattern
  Einzähler             Klick-Takt(e) vor dem Start

RASTER & SWING
  Raster                16tel, 8tel-Triolen, 16tel-Triolen oder 8tel
  Swing                 Lage der Off-Beat-Note: 50 % gerade, 67 % Triole, 75 % punktiert
  Auto / 8tel / 16tel   worauf im geraden Raster geswingt wird

PATTERNS & KETTE
  1 … 8                 Pattern bearbeiten   + Kopie / + Leer / Löschen / Leeren
  + Fill                neues Pattern: Groove mit Fill am Ende, nochmal klicken = anderer Fill
  Steps                 Länge des Patterns (z. B. 12 für 3/4, 20 für 5/4)
  Kette                 Reihenfolge für Song-Modus und Export, z. B. „1x3 2“ = 1 1 1 2

DATEI
  Neu / Duplizieren     neuer Groove bzw. Kopie, das Original bleibt erhalten
  Speichern             songs/<Name>.toml – vorhandene Dateien erst nach zweitem Klick
  Preset / Song laden   Groove-Bibliothek bzw. eigene Songs
  Datei öffnen …        Song (.toml) aus einem beliebigen Verzeichnis laden

EXPORT
  Wiederholungen        wie oft die Kette hintereinander geschrieben wird
  Einzähler, Klick      Takte vorweg bzw. Metronom auf jedem Schlag
  Stereo | Mono         wirkt auf Wiedergabe und WAV
  WAV exportieren       songs/<Name>.wav, 44,1 kHz, 16 Bit
"""

"Figure mit der Kurzhilfe."
help_figure() = with_theme(DM_THEME) do
    f = Figure(size = (760, 625), figure_padding = 16)
    panel!(f[1, 1])
    Label(f[1, 1], HELP_TEXT; font = "DejaVu Sans Mono", fontsize = 13, justification = :left,
          halign = :left, valign = :top, color = C_TEXT, padding = (22, 22, 20, 20),
          tellwidth = false, tellheight = false)
    f
end

"Öffnet ein Fenster mit der Kurzhilfe."
show_help() = display(GLMakie.Screen(; title = "DrumMachine – Hilfe"), help_figure())

const RASTER_OPTS = [("16tel (4 pro Schlag)", 4), ("Triolen (3 pro Schlag)", 3),
                     ("16tel-Triolen (6 pro Schlag)", 6), ("8tel (2 pro Schlag)", 2)]
const SWING_OPTS = [("Auto", 0), ("auf 8tel", 8), ("auf 16tel", 16)]
const STEP_OPTS = [3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 15, 16, 18, 20, 21, 24, 28, 30, 32]
const MAXPATTERNS = 8

"Zählsilben für die Kopfzeile: 1 e + a / 1 + a / 1 la li + la li / 1 +."
function count_labels(steps::Int, spb::Int)
    syl = spb == 4 ? ("", "e", "+", "a") : spb == 3 ? ("", "+", "a") : spb == 6 ? ("", "la", "li", "+", "la", "li") :
          spb == 2 ? ("", "+") : ntuple(_ -> "", spb)
    [((s - 1) % spb == 0 ? string((s - 1) ÷ spb + 1) : syl[(s-1)%spb+1]) for s in 1:steps]
end

"""
Öffnet den Datei-Dialog des Systems (zenity oder kdialog) und liefert den gewählten Pfad,
`""` bei Abbruch oder `nothing`, wenn kein Dialog-Programm installiert ist. Blockiert nur
die aufrufende Task, die GUI läuft weiter.
"""
function pick_song_file(startdir::AbstractString = SONG_DIR)
    dir = isdir(startdir) ? startdir : homedir()
    cmd = if Sys.which("zenity") !== nothing
        `zenity --file-selection "--title=Song laden" "--filename=$(joinpath(dir, ""))" "--file-filter=Songs (*.toml) | *.toml" "--file-filter=Alle Dateien | *"`
    elseif Sys.which("kdialog") !== nothing
        `kdialog --title "Song laden" --getopenfilename $dir "*.toml|Songs (*.toml)"`
    else
        return nothing
    end
    out = IOBuffer()
    p = Base.run(pipeline(ignorestatus(cmd); stdout = out, stderr = devnull))   # `run` ist hier die GUI
    success(p) || return ""                       # Abbrechen
    return strip(String(take!(out)))
end

function list_songs()
    isdir(SONG_DIR) || return String[]
    sort([splitext(f)[1] for f in readdir(SONG_DIR) if endswith(f, ".toml")])
end

"Kurzbeschreibung für die Statuszeile, z. B. `100 BPM · Swing 63 % (Auto) · Kette 1 1 2`."
function song_summary(s::Song)
    pct = round(Int, 100s.swing)
    sw = s.steps_per_beat in (3, 6) ? (s.swing == 2 / 3 ? "exakte Triolen" : "Triolen-Swing $pct %") :
         s.swing == 0.5 ? "kein Swing" : "Swing $pct % ($(s.swing_on == 0 ? "Auto" : "auf $(s.swing_on)tel"))"
    return "$(round(Int, s.bpm)) BPM · $sw · Kette $(chain_string(s.chain))"
end

fmt_time(sec) = string(floor(Int, sec ÷ 60), ":", lpad(round(Int, sec % 60) % 60, 2, '0'))

"""
    run(; song = preset("Rock: 8tel"), block = true)

Startet die Drum-Machine. `block=false` kehrt sofort zurück (für die REPL) und gibt
`(fig, eng)` zurück.
"""
function run(; song::Song = preset("Rock: 8tel"), block::Bool = true, audio::Bool = true)
    GLMakie.activate!(title = "DrumMachine.jl")
    fig, eng, tick! = build_gui(song; audio)
    screen = display(fig)
    # Playhead-Anzeige (läuft auf dem Haupt-Thread)
    @async begin
        while isopen(screen)
            tick!()
            sleep(1 / 60)
        end
        stop_audio!(eng)
    end
    if block
        wait(screen)
        return nothing
    end
    return fig, eng
end

"""
    build_gui(song; audio=true) -> (fig, eng, tick!)

Baut Figure und Engine auf (ohne Fenster). `tick!()` aktualisiert Playhead & Anzeige.
"""
build_gui(song::Song; audio::Bool = true) = with_theme(() -> _build_gui(song; audio), DM_THEME)

function _build_gui(song::Song; audio::Bool = true)
    kits = available_kits()
    kitnames = [k.name for k in kits]
    kitidx = something(findfirst(==(song.kit), kitnames), 1)
    eng = Engine(song, kits[kitidx])
    eng.song.kit = kitnames[kitidx]
    audio && start_audio!(eng)

    fig = Figure(size = (1320, 975), backgroundcolor = C_BG, fontsize = 14, figure_padding = 18)
    HELP = "Bereit.  Linksklick: Schlag an/aus · Rechtsklick: Ghost → normal → Akzent · Leertaste: Play/Stop · ? = Hilfe"
    status = Observable(HELP)

    # ---------------------------------------------------------------- Kopfzeile
    hdr = fig[1, 1] = GridLayout(tellwidth = false, halign = :left)
    Label(hdr[1, 1], "DRUM MACHINE", font = :bold, fontsize = 22, color = C_TEXT)
    Label(hdr[1, 2], "Groove  ·  Vorhören  ·  WAV-Export", fontsize = 14, color = C_TEXT2, padding = (14, 0, 0, 0))
    hdr_r = fig[1, 1] = GridLayout(tellwidth = false, halign = :right)
    helpbtn = Button(hdr_r[1, 1], label = "?", width = 34, height = 34, cornerradius = 17,
                     fontsize = 17, font = :bold)

    # ---------------------------------------------------------------- Transport
    panel!(fig[2, 1])
    tbox = fig[2, 1] = GridLayout(tellwidth = false, halign = :left, alignmode = Outside(14))
    top = tbox[1, 1] = GridLayout(halign = :left)
    playbtn = Button(top[1, 1], label = "▶  Play", width = 100, buttoncolor = C_ACTIVE, labelcolor = C_BG,
                     buttoncolor_hover = C_LEVEL_H[2], labelcolor_hover = C_BG, labelcolor_active = C_BG,
                     font = :bold)
    modebtn = Button(top[1, 2], label = "Modus: Pattern", width = 140)
    Label(top[1, 3], "Einzähler", halign = :right, color = C_TEXT2)
    ci_toggle = Toggle(top[1, 4], active = false)
    Label(top[1, 5], "BPM", halign = :right, color = C_TEXT2)
    bpm_sl = Slider(top[1, 6], range = 30:1:260, startvalue = song.bpm, width = 160)
    bpm_lab = Label(top[1, 7], "", width = 40, font = :bold)
    Label(top[1, 8], "Swing", halign = :right, color = C_TEXT2)
    sw_sl = Slider(top[1, 9], range = 50:1:75, startvalue = round(Int, 100song.swing), width = 110)
    sw_lab = Label(top[1, 10], "", width = 40, font = :bold)
    sw_menu = Menu(top[1, 11], options = first.(SWING_OPTS), width = 95)

    top2 = tbox[2, 1] = GridLayout(halign = :left)
    Label(top2[1, 1], "Raster", halign = :right, color = C_TEXT2)
    raster_menu = Menu(top2[1, 2], options = first.(RASTER_OPTS), width = 225)
    Label(top2[1, 3], "Kit", halign = :right, color = C_TEXT2)
    kit_menu = Menu(top2[1, 4], options = kitnames, default = kitnames[kitidx], width = 150)
    Label(top2[1, 5], "FX", halign = :right, color = C_TEXT2)
    fx_menu = Menu(top2[1, 6], options = FX_NAMES, default = song.fx, width = 90)
    Label(top2[1, 7], "Anteil", halign = :right, color = C_TEXT2)
    fx_sl = Slider(top2[1, 8], range = 0:0.01:1, startvalue = song.fxmix, width = 100)
    Label(top2[1, 9], "Master", halign = :right, color = C_TEXT2)
    mst_sl = Slider(top2[1, 10], range = 0:0.01:1.5, startvalue = song.master, width = 100)
    rowgap!(tbox, 10)

    # ---------------------------------------------------------------- Patterns
    panel!(fig[3, 1])
    pbox = fig[3, 1] = GridLayout(tellwidth = false, halign = :left, alignmode = Outside(14))
    pbar = pbox[1, 1] = GridLayout(halign = :left)
    Label(pbar[1, 1], "PATTERN", font = :bold, color = C_TEXT2, width = 70, halign = :left)
    patbtns = [Button(pbar[1, 1+i], label = string(i), width = 40) for i in 1:MAXPATTERNS]
    addcopy = Button(pbar[1, MAXPATTERNS+2], label = "+ Kopie")
    addempty = Button(pbar[1, MAXPATTERNS+3], label = "+ Leer")
    fillbtn = Button(pbar[1, MAXPATTERNS+4], label = "+ Fill")
    delbtn = Button(pbar[1, MAXPATTERNS+5], label = "Löschen")
    clrbtn = Button(pbar[1, MAXPATTERNS+6], label = "Leeren")
    pbar2 = pbox[2, 1] = GridLayout(halign = :left)
    Label(pbar2[1, 1], "Steps", halign = :left, color = C_TEXT2, width = 70)
    steps_menu = Menu(pbar2[1, 2], options = string.(STEP_OPTS), width = 60)
    Label(pbar2[1, 3], "Kette", halign = :right, color = C_TEXT2)
    chain_tb = Textbox(pbar2[1, 4], stored_string = chain_string(song.chain), width = 260,
                       placeholder = "z. B. 1x3 2", reset_on_defocus = true)
    Label(pbar2[1, 5], "für Song-Modus und Export", color = C_DIM, fontsize = 12)
    rowgap!(pbox, 10)

    # ---------------------------------------------------------------- Raster
    panel!(fig[4, 1])
    grid = fig[4, 1] = GridLayout(halign = :left, tellwidth = false, alignmode = Outside(14))
    headax = Axis(grid[1, 5], height = 22, backgroundcolor = :transparent)
    hidedecorations!(headax); hidespines!(headax)
    headtxt = Observable(String[])
    headpos = Observable(Point2f[])
    text!(headax, headpos; text = headtxt, align = (:center, :center), fontsize = 13, color = C_TEXT2)

    cellrects = [Rect2f(s - 1 + 0.06, 0.1, 0.88, 0.8) for s in 1:MAXSTEPS]
    rowcolors = [Observable(fill(C_OFF_A, MAXSTEPS)) for _ in 1:NTRACKS]
    axes = Axis[]
    mutebtns = Button[]; solobtns = Button[]; volsls = Slider[]; namebtns = Button[]
    fx_track = Ref(1)                          # Spur, deren Effekte rechts angezeigt werden
    for t in 1:NTRACKS
        r = t + 1
        nb = Button(grid[r, 1], label = TRACKS[t][2], width = 100)
        push!(namebtns, nb)
        on(nb.clicks) do _
            put!(eng.pads, (t, 2))
            fx_track[] = t
            refresh_fx!()
        end
        mb = Button(grid[r, 2], label = "M", width = 30)
        sb = Button(grid[r, 3], label = "S", width = 30)
        vs = Slider(grid[r, 4], range = 0:0.01:1.5, startvalue = song.tracks[t].vol, width = 90)
        push!(mutebtns, mb); push!(solobtns, sb); push!(volsls, vs)
        ax = Axis(grid[r, 5], height = 34, backgroundcolor = :transparent,
                  xrectzoom = false, yrectzoom = false, xzoomlock = true, yzoomlock = true,
                  xpanlock = true, ypanlock = true)
        hidedecorations!(ax); hidespines!(ax)
        for k in (:rectanglezoom, :scrollzoom, :dragpan, :limitreset)
            try deregister_interaction!(ax, k) catch end
        end
        poly!(ax, cellrects; color = rowcolors[t], strokewidth = 0)
        push!(axes, ax)
        register_interaction!(ax, :cellclick) do ev::MouseEvent, _
            ev.type in (MouseEventTypes.leftclick, MouseEventTypes.rightclick) || return
            p = cur_pattern()
            s = floor(Int, ev.data[1]) + 1
            1 <= s <= p.steps || return
            v = p.grid[t, s]
            if ev.type == MouseEventTypes.leftclick
                nv = v == 0 ? 0x02 : 0x00
            else
                nv = v == 0 ? 0x01 : v == 3 ? 0x01 : v + 0x01
            end
            p.grid[t, s] = nv
            nv > 0 && !eng.playing && put!(eng.pads, (t, Int(nv)))
            refresh_row!(t)
            return Consume(true)
        end
    end
    colgap!(grid, 8); rowgap!(grid, 4)
    leg = Label(grid[NTRACKS+2, 5], "Ghost (o)  ·  normal (x)  ·  Akzent (X)     Klick auf den Spurnamen = Vorhören + Effekte",
                halign = :left, color = C_TEXT2, fontsize = 12, tellwidth = false)

    # Spur-Effekte (rechts neben dem Raster): EQ + Chorus/Flanger der gewählten Spur
    fxbox = grid[1:NTRACKS+2, 6] = GridLayout(valign = :top, halign = :left)
    Label(fxbox[1, 1:3], "SPUR-EFFEKTE", font = :bold, color = C_TEXT2, halign = :left)
    fx_title = Label(fxbox[2, 1:3], "", font = :bold, color = C_ACTIVE, halign = :left, fontsize = 16)
    fx_sliders = Dict{Symbol,Slider}()
    fx_vals = Dict{Symbol,Observable{String}}()
    midf_range = [200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6000]   # Terzen
    rate_range = vcat(0.05:0.05:1, 1.1:0.1:5)
    fx_rows = [(:eq_low, "Tiefen", -12:0.5:12, v -> "$(v) dB"),
               (:eq_mid, "Mitten", -12:0.5:12, v -> "$(v) dB"),
               (:eq_midf, "Mitten bei", midf_range, v -> v >= 1000 ? "$(round(v / 1000, digits = 1)) kHz" : "$(round(Int, v)) Hz"),
               (:eq_high, "Höhen", -12:0.5:12, v -> "$(v) dB"),
               (:mod_mix, "Mix", 0:0.01:1, v -> "$(round(Int, 100v)) %"),
               (:mod_rate, "Rate", rate_range, v -> "$(round(v, digits = 2)) Hz"),
               (:mod_depth, "Tiefe", 0:0.01:1, v -> "$(round(Int, 100v)) %"),
               (:mod_fb, "Feedback", 0:0.01:0.9, v -> "$(round(Int, 100v)) %")]
    Label(fxbox[3, 1:3], "EQ", color = C_DIM, fontsize = 12, halign = :left)
    Label(fxbox[8, 1], "Effekt", color = C_TEXT2, halign = :left)
    mod_menu = Menu(fxbox[8, 2:3], options = MOD_NAMES, default = "Aus", width = 150)
    for (k, (f, name, rng, fmt)) in enumerate(fx_rows)
        row = k <= 4 ? 3 + k : 4 + k
        Label(fxbox[row, 1], name, color = C_TEXT2, halign = :left)
        sl = Slider(fxbox[row, 2], range = rng, startvalue = getfield(TrackParams(), f), width = 130)
        val = Observable("")
        Label(fxbox[row, 3], val, color = C_TEXT, halign = :left, width = 62, fontsize = 12)
        on(v -> (val[] = fmt(v)), sl.value; update = true)
        fx_sliders[f] = sl; fx_vals[f] = val
    end
    fx_reset = Button(fxbox[13, 1:3], label = "Effekte der Spur zurücksetzen")
    rowgap!(fxbox, 4); colgap!(fxbox, 6)

    # ---------------------------------------------------------------- Datei / Export
    panel!(fig[5, 1])
    fbox = fig[5, 1] = GridLayout(tellwidth = false, halign = :left, alignmode = Outside(14))
    bot = fbox[1, 1] = GridLayout(halign = :left)
    Label(bot[1, 1], "DATEI", font = :bold, color = C_TEXT2, width = 70, halign = :left)
    newbtn = Button(bot[1, 2], label = "Neu")
    dupbtn = Button(bot[1, 3], label = "Duplizieren")
    Label(bot[1, 4], "Name", halign = :right, color = C_TEXT2)
    name_tb = Textbox(bot[1, 5], stored_string = song.name, width = 300, reset_on_defocus = true)
    savebtn = Button(bot[1, 6], label = "Speichern", width = 130)
    lbox = fbox[2, 1] = GridLayout(halign = :left)
    Label(lbox[1, 1], "LADEN", font = :bold, color = C_TEXT2, width = 70, halign = :left)
    preset_menu = Menu(lbox[1, 2], options = PRESET_NAMES, default = nothing, prompt = "Preset laden …", width = 340)
    load_menu = Menu(lbox[1, 3], options = vcat(["—"], list_songs()), default = nothing, prompt = "Eigenen Song laden …",
                     width = 260)
    filebtn = Button(lbox[1, 4], label = "Datei öffnen …")
    bot2 = fbox[3, 1] = GridLayout(halign = :left)
    Label(bot2[1, 1], "EXPORT", font = :bold, color = C_TEXT2, width = 70, halign = :left)
    Label(bot2[1, 2], "Wiederholungen", halign = :right, color = C_TEXT2)
    rep_tb = Textbox(bot2[1, 3], stored_string = string(song.repeats), validator = Int, width = 50,
                     reset_on_defocus = true)
    Label(bot2[1, 4], "Einzähler (Takte)", halign = :right, color = C_TEXT2)
    ci_menu = Menu(bot2[1, 5], options = string.(0:4), default = string(song.countin), width = 50)
    Label(bot2[1, 6], "Klick", halign = :right, color = C_TEXT2)
    click_toggle = Toggle(bot2[1, 7], active = song.click)
    Label(bot2[1, 8], "   Stereo", halign = :right, color = C_TEXT2)
    mono_toggle = Toggle(bot2[1, 9], active = song.mono)
    Label(bot2[1, 10], "Mono", halign = :left, color = C_TEXT2)
    expbtn = Button(bot2[1, 11], label = "WAV exportieren", buttoncolor = C_ACTIVE, labelcolor = C_BG,
                    buttoncolor_hover = C_LEVEL_H[2], labelcolor_hover = C_BG, labelcolor_active = C_BG,
                    font = :bold)
    explab = Label(bot2[1, 12], "", color = C_TEXT2)
    rowgap!(fbox, 10)

    Label(fig[6, 1], status, halign = :left, tellwidth = false, color = C_TEXT2, fontsize = 13)
    rowgap!(fig.layout, 12)
    colsize!(fig.layout, 1, Relative(1))      # volle Breite, alles linksbündig
    on(_ -> show_help(), helpbtn.clicks)

    # ================================================================ Logik
    cur_pattern() = eng.song.patterns[clamp(eng.edit_pat, 1, length(eng.song.patterns))]
    playhead = Ref(-1)

    function refresh_row!(t)
        p = cur_pattern(); spb = eng.song.steps_per_beat
        cols = rowcolors[t][]
        for s in 1:MAXSTEPS
            v = p.grid[t, s]
            head = (s - 1) == playhead[]
            cols[s] = v > 0 ? (head ? C_LEVEL_H[v] : C_LEVEL[v]) :
                      head ? C_HEAD : (iseven((s - 1) ÷ spb) ? C_OFF_A : C_OFF_B)
        end
        notify(rowcolors[t])
    end

    function refresh_grid!()
        p = cur_pattern()
        for (t, ax) in enumerate(axes)
            limits!(ax, 0, p.steps, 0, 1)
            refresh_row!(t)
        end
        limits!(headax, 0, p.steps, 0, 1)
        headtxt[] = count_labels(p.steps, eng.song.steps_per_beat)
        headpos[] = [Point2f(s - 0.5, 0.5) for s in 1:p.steps]
        k = findfirst(==(p.steps), STEP_OPTS)
        k === nothing || (steps_menu.i_selected[] = k)
    end

    function refresh_tracks!()
        for t in 1:NTRACKS
            tp = eng.song.tracks[t]
            mutebtns[t].buttoncolor[] = tp.mute ? C_MUTE : C_BTN
            solobtns[t].buttoncolor[] = tp.solo ? C_SOLO : C_BTN
        end
    end

    fx_updating = Ref(false)                   # Slider werden gerade aus der Spur gesetzt
    function refresh_fx!()
        t = fx_track[]
        tp = eng.song.tracks[t]
        fx_updating[] = true
        try
            fx_title.text[] = TRACKS[t][2]
            for (f, sl) in fx_sliders
                set_close_to!(sl, getfield(tp, f))
            end
            mod_menu.i_selected[] = tp.mod
        finally
            fx_updating[] = false
        end
        for (k, b) in enumerate(namebtns)
            on_fx = has_trackfx(eng.song.tracks[k])
            b.labelcolor[] = on_fx ? C_ACTIVE : C_TEXT
            b.buttoncolor[] = k == t ? C_BTN_A : C_BTN
        end
    end

    function refresh_patbtns!()
        n = length(eng.song.patterns)
        playing = eng.playing ? eng.shown_pat[] : 0
        for (i, b) in enumerate(patbtns)
            b.buttoncolor[] = i == eng.edit_pat ? C_ACTIVE : i <= n ? C_BTN : C_PANEL
            b.labelcolor[] = i == eng.edit_pat ? C_BG : i <= n ? C_TEXT : C_DIM
            b.label[] = i == playing ? "▸$i" : string(i)
        end
    end

    function refresh_export_info!()
        s = eng.song
        explab.text[] = "≈ $(fmt_time(song_seconds(s))) min"
    end

    "Alle Widgets aus `eng.song` neu setzen (nach Laden/Preset)."
    function refresh_all!()
        s = eng.song
        set_close_to!(bpm_sl, s.bpm)
        set_close_to!(sw_sl, round(Int, 100s.swing))
        sw_menu.i_selected[] = something(findfirst(o -> o[2] == s.swing_on, SWING_OPTS), 1)
        raster_menu.i_selected[] = something(findfirst(o -> o[2] == s.steps_per_beat, RASTER_OPTS), 1)
        fx_menu.i_selected[] = something(findfirst(==(s.fx), FX_NAMES), 1)
        set_close_to!(fx_sl, s.fxmix); set_close_to!(mst_sl, s.master)
        for t in 1:NTRACKS; set_close_to!(volsls[t], s.tracks[t].vol); end
        chain_tb.stored_string[] = chain_string(s.chain); chain_tb.displayed_string[] = chain_string(s.chain)
        name_tb.stored_string[] = s.name; name_tb.displayed_string[] = s.name
        rep_tb.stored_string[] = string(s.repeats); rep_tb.displayed_string[] = string(s.repeats)
        ci_menu.i_selected[] = clamp(s.countin, 0, 4) + 1
        # Toggle nur bei echter Änderung setzen: Makies Toggle animiert sonst einen Wechsel
        # und zeigt danach den falschen Zustand an.
        set_toggle!(click_toggle, s.click)
        set_toggle!(mono_toggle, s.mono)
        k = findfirst(==(s.kit), kitnames)
        k !== nothing && (kit_menu.i_selected[] = k)
        refresh_tracks!(); refresh_grid!(); refresh_patbtns!(); refresh_export_info!(); refresh_fx!()
    end

    safe(name) = replace(strip(name), r"[^\w\-äöüÄÖÜß ]" => "_")
    song_path(name) = joinpath(SONG_DIR, safe(name) * ".toml")
    "Erster freier Name: `base`, `base 2`, `base 3`, …"
    function unique_name(base)
        name = base; k = 2
        while isfile(song_path(name))
            name = "$base $k"; k += 1
        end
        return name
    end
    pending_overwrite = Ref("")
    function cancel_overwrite!()
        pending_overwrite[] == "" && return
        pending_overwrite[] = ""
        savebtn.label[] = "Speichern"
        savebtn.buttoncolor[] = C_BTN
        savebtn.labelcolor[] = C_TEXT
    end

    function set_song!(s::Song)
        cancel_overwrite!()
        was = eng.playing
        was && stop!(eng)
        lock(eng.lock) do
            eng.song = s
            eng.edit_pat = 1
            k = findfirst(==(s.kit), kitnames)
            if k === nothing
                s.kit = eng.kit.name
            else
                eng.kit = kits[k]
            end
            apply_fx!(eng)
        end
        refresh_all!()
        was && play!(eng)
    end

    function toggle_play()
        if eng.playing
            stop!(eng)
            playbtn.label[] = "▶  Play"
        else
            eng.live_countin = ci_toggle.active[]
            play!(eng)
            playbtn.label[] = "■  Stop"
        end
    end

    # Transport
    on(_ -> toggle_play(), playbtn.clicks)
    on(modebtn.clicks) do _
        eng.songmode = !eng.songmode
        modebtn.label[] = eng.songmode ? "Modus: Song" : "Modus: Pattern"
        eng.playing && play!(eng)
    end
    on(bpm_sl.value) do v
        eng.song.bpm = v; bpm_lab.text[] = string(v); refresh_export_info!()
    end
    on(sw_sl.value) do v
        eng.song.swing = v == 67 ? 2 / 3 : v / 100       # 67 % = exakte Triole
        sw_lab.text[] = "$v%"
        refresh_export_info!()
    end
    on(sw_menu.selection) do sel
        sel === nothing && return
        eng.song.swing_on = SWING_OPTS[findfirst(o -> o[1] == sel, SWING_OPTS)][2]
        refresh_export_info!()
    end
    on(raster_menu.selection) do sel
        sel === nothing && return
        old = eng.song.steps_per_beat
        new = RASTER_OPTS[findfirst(o -> o[1] == sel, RASTER_OPTS)][2]
        eng.song.steps_per_beat = new
        # Beim Wechsel zwischen geraden und Triolen-Rastern neutralen Swing setzen
        if (old in (3, 6)) != (new in (3, 6)) && eng.song.swing == default_swing(old)
            eng.song.swing = default_swing(new)
            set_close_to!(sw_sl, round(Int, 100eng.song.swing))
        end
        refresh_grid!(); refresh_export_info!()
    end
    on(kit_menu.selection) do sel
        sel === nothing && return
        k = findfirst(==(sel), kitnames)
        lock(eng.lock) do
            eng.kit = kits[k]
        end
        eng.song.kit = sel
    end
    on(fx_menu.selection) do sel
        sel === nothing && return
        eng.song.fx = sel; apply_fx!(eng)
    end
    on(v -> (eng.song.fxmix = v; apply_fx!(eng)), fx_sl.value)
    on(v -> (eng.song.master = v), mst_sl.value)

    # Spuren
    for t in 1:NTRACKS
        on(mutebtns[t].clicks) do _
            eng.song.tracks[t].mute = !eng.song.tracks[t].mute; refresh_tracks!()
        end
        on(solobtns[t].clicks) do _
            eng.song.tracks[t].solo = !eng.song.tracks[t].solo; refresh_tracks!()
        end
        on(v -> (eng.song.tracks[t].vol = v), volsls[t].value)
    end
    # Spur-Effekte
    for (f, sl) in fx_sliders
        on(sl.value) do v
            fx_updating[] && return
            tp = eng.song.tracks[fx_track[]]
            lock(eng.lock) do
                setfield!(tp, f, Float32(v))
            end
            f in (:eq_low, :eq_mid, :eq_high) && refresh_fx!()     # Anzeige „Spur hat Effekte“
        end
    end
    on(mod_menu.selection) do sel
        (sel === nothing || fx_updating[]) && return
        tp = eng.song.tracks[fx_track[]]
        MOD_NAMES[tp.mod] == sel && return
        lock(eng.lock) do
            set_mod!(tp, sel)
        end
        refresh_fx!()
        sel == "Aus" || (status[] = "$(sel) auf $(TRACKS[fx_track[]][2]) – Mix, Rate, Tiefe und Feedback einstellbar.")
    end
    on(fx_reset.clicks) do _
        tp = eng.song.tracks[fx_track[]]
        d = TrackParams()
        lock(eng.lock) do
            for f in (:eq_low, :eq_mid, :eq_midf, :eq_high, :mod, :mod_mix, :mod_rate, :mod_depth, :mod_fb)
                setfield!(tp, f, getfield(d, f))
            end
        end
        refresh_fx!()
    end

    # Patterns
    for (i, b) in enumerate(patbtns)
        on(b.clicks) do _
            i <= length(eng.song.patterns) || return
            eng.edit_pat = i
            refresh_grid!(); refresh_patbtns!()
        end
    end
    function add_pattern!(p::Pattern)
        if length(eng.song.patterns) >= MAXPATTERNS
            status[] = "Maximal $MAXPATTERNS Patterns."
            return
        end
        lock(eng.lock) do
            push!(eng.song.patterns, p)
        end
        eng.edit_pat = length(eng.song.patterns)
        refresh_grid!(); refresh_patbtns!()
        status[] = "Pattern $(eng.edit_pat) angelegt. Für Song/Export in die Kette eintragen (z. B. \"1x3 $(eng.edit_pat)\")."
    end
    on(_ -> add_pattern!(copy(cur_pattern())), addcopy.clicks)
    on(_ -> add_pattern!(Pattern(cur_pattern().steps)), addempty.clicks)
    # Fill: neues Pattern aus dem aktuellen, letzte Schläge als Fill. Erneuter Klick auf das
    # (unveränderte) Fill-Pattern probiert den nächsten Stil aus.
    fill_src = Ref{Union{Nothing,Pattern}}(nothing)   # Groove, aus dem der Fill entstand
    fill_pat = Ref{Union{Nothing,Pattern}}(nothing)   # zuletzt erzeugter Fill (zum Wiedererkennen)
    fill_style = Ref(1)
    fill_from = Ref(1)                                # Nummer des Ausgangs-Patterns (für den Ketten-Tipp)
    on(fillbtn.clicks) do _
        s = eng.song
        cur = cur_pattern()
        if fill_pat[] === cur && fill_src[] !== nothing && cur.grid == make_fill(fill_src[], s.steps_per_beat, fill_style[]).grid
            fill_style[] += 1
            q = make_fill(fill_src[], s.steps_per_beat, fill_style[])
            lock(eng.lock) do
                cur.steps = q.steps
                copyto!(cur.grid, q.grid)
            end
            refresh_grid!()
        else
            length(s.patterns) >= MAXPATTERNS && (status[] = "Maximal $MAXPATTERNS Patterns."; return)
            fill_src[] = copy(cur)
            fill_style[] = 1
            add_pattern!(make_fill(cur, s.steps_per_beat, 1))
            fill_pat[] = cur_pattern()
            fill_from[] = something(findfirst(p -> p === cur, s.patterns), 1)
        end
        n = eng.edit_pat
        status[] = "Fill „$(fill_name(fill_style[]))“ in Pattern $n – nochmal „+ Fill“ für den nächsten Stil. " *
                   "Kette z. B. \"$(fill_from[])x3 $n\"."
    end
    on(delbtn.clicks) do _
        s = eng.song
        length(s.patterns) <= 1 && return
        k = eng.edit_pat
        lock(eng.lock) do
            deleteat!(s.patterns, k)
            s.chain = [i > k ? i - 1 : i for i in s.chain if i != k]
            isempty(s.chain) && push!(s.chain, 1)
            eng.edit_pat = clamp(k, 1, length(s.patterns))
            eng.pat > length(s.patterns) && (eng.pat = eng.edit_pat)
            eng.seq = [p > length(s.patterns) ? -1 : p for p in eng.seq]
        end
        chain_tb.stored_string[] = chain_string(s.chain); chain_tb.displayed_string[] = chain_string(s.chain)
        refresh_grid!(); refresh_patbtns!(); refresh_export_info!()
    end
    on(clrbtn.clicks) do _
        fill!(cur_pattern().grid, 0x00); refresh_grid!()
    end
    on(steps_menu.selection) do sel
        sel === nothing && return
        n = parse(Int, sel)
        p = cur_pattern()
        p.steps == n && return
        p.steps = n
        refresh_grid!(); refresh_export_info!()
    end
    on(chain_tb.stored_string) do str
        str === nothing && return
        c = parse_chain(str, length(eng.song.patterns))
        if isempty(c)
            status[] = "Kette ungültig – Beispiel: \"1 1 1 2\" oder \"1x3 2\"."
            return
        end
        eng.song.chain = c
        status[] = "Kette: $(chain_string(c))"
        refresh_export_info!()
        eng.playing && eng.songmode && play!(eng)
    end

    # Datei
    on(preset_menu.selection) do sel
        sel === nothing && return
        s = preset(sel)
        s.kit = eng.song.kit                  # Presets behalten das gewählte Kit
        set_song!(s)
        status[] = "Preset \"$sel\" geladen ($(song_summary(eng.song)))."
        preset_menu.i_selected[] = 0          # gleiches Preset später erneut wählbar
    end
    on(name_tb.stored_string) do str
        str === nothing && return
        eng.song.name = str
        cancel_overwrite!()
    end
    on(savebtn.clicks) do _
        path = song_path(eng.song.name)
        if isfile(path) && pending_overwrite[] != path
            # Erster Klick auf eine vorhandene Datei: nur nachfragen
            pending_overwrite[] = path
            savebtn.label[] = "Überschreiben?"
            savebtn.buttoncolor[] = C_MUTE
            savebtn.labelcolor[] = C_TEXT
            status[] = "\"$(basename(path))\" gibt es schon. Nochmal klicken zum Überschreiben, " *
                       "oder einen anderen Namen eingeben bzw. „Duplizieren“."
            return
        end
        cancel_overwrite!()
        save_song(path, eng.song)
        load_menu.options[] = vcat(["—"], list_songs())
        status[] = "Gespeichert: $path  ($(song_summary(eng.song)))"
    end
    on(newbtn.clicks) do _
        old = eng.song
        spb = old.steps_per_beat
        s = Song(name = unique_name("Neuer Groove"), bpm = old.bpm, steps_per_beat = spb,
                 swing = old.swing, swing_on = old.swing_on,
                 patterns = [Pattern(spb in (2, 4) ? 16 : 4spb)], kit = old.kit,
                 repeats = old.repeats, countin = old.countin, click = old.click, mono = old.mono)
        set_song!(s)
        status[] = "Neuer Groove \"$(s.name)\" angelegt (BPM, Swing, Raster und Kit übernommen)."
    end
    on(dupbtn.clicks) do _
        s = copy(eng.song)
        s.name = unique_name(s.name * " Kopie")
        set_song!(s)
        status[] = "Kopie \"$(s.name)\" angelegt – das Original bleibt unverändert."
    end
    on(load_menu.selection) do sel
        (sel === nothing || sel == "—") && return
        path = joinpath(SONG_DIR, sel * ".toml")
        try
            set_song!(load_song(path))
            status[] = "Geladen: $path  ($(song_summary(eng.song)))"
        catch e
            status[] = "Fehler beim Laden: $(sprint(showerror, e))"
        end
        load_menu.i_selected[] = 0            # derselbe Song lässt sich erneut (von Platte) laden
    end
    last_dir = Ref(SONG_DIR)
    dialog_open = Ref(false)
    on(filebtn.clicks) do _
        dialog_open[] && return
        dialog_open[] = true
        status[] = "Datei-Dialog geöffnet …"
        @async try
            path = pick_song_file(last_dir[])
            if path === nothing
                status[] = "Kein Datei-Dialog gefunden – bitte zenity oder kdialog installieren."
            elseif path != ""
                last_dir[] = dirname(path)
                set_song!(load_song(path))
                status[] = "Geladen: $path  ($(song_summary(eng.song)))"
            else
                status[] = "Laden abgebrochen."
            end
        catch e
            status[] = "Fehler beim Laden: $(sprint(showerror, e))"
        finally
            dialog_open[] = false
        end
    end

    # Export
    on(rep_tb.stored_string) do str
        str === nothing && return
        eng.song.repeats = clamp(parse(Int, str), 1, 999); refresh_export_info!()
    end
    on(ci_menu.selection) do sel
        sel === nothing && return
        eng.song.countin = parse(Int, sel); refresh_export_info!()
    end
    on(v -> (eng.song.click = v), click_toggle.active)
    on(mono_toggle.active) do v
        eng.song.mono = v
        status[] = v ? "Mono: Wiedergabe und Export einkanalig." : "Stereo: Wiedergabe und Export zweikanalig."
    end
    on(expbtn.clicks) do _
        s = eng.song
        path = joinpath(SONG_DIR, safe(s.name) * ".wav")
        status[] = "Exportiere …"
        try
            t = @elapsed (path = export_wav(path, s, eng.kit))
            status[] = "WAV geschrieben: $path  ($(fmt_time(song_seconds(s))) min, $(s.mono ? "mono" : "stereo"), $(s.bpm) BPM, " *
                       "$(s.repeats)× Kette, Einzähler $(s.countin) Takt(e), $(round(t, digits = 1)) s)"
        catch e
            status[] = "Export fehlgeschlagen: $(sprint(showerror, e))"
        end
    end

    # Tastatur: Leertaste = Play/Stop (nicht während Texteingabe)
    on(events(fig).keyboardbutton) do ev
        ev.action == Keyboard.press || return
        any(tb -> tb.focused[], (chain_tb, name_tb, rep_tb)) && return
        if ev.key == Keyboard.space
            toggle_play()
        end
    end

    bpm_lab.text[] = string(round(Int, song.bpm)); sw_lab.text[] = "$(round(Int, 100song.swing))%"
    refresh_all!()
    status[] = HELP

    last = Ref((-2, -2, false, 0))
    function tick!()
        st = eng.playing ? eng.shown_step[] : -1
        pt = eng.shown_pat[]
        sp = eng.shown_seqpos[]
        cur = (st, pt, eng.playing, sp)
        cur == last[] && return
        # Song-Modus: Raster folgt dem gerade spielenden Pattern
        if eng.songmode && eng.playing && 1 <= pt <= length(eng.song.patterns)
            if pt != eng.edit_pat
                eng.edit_pat = pt
                refresh_grid!()
            end
            if sp != last[][4]
                seq = eng.seq
                k = count(>(0), @view seq[1:min(sp, length(seq))])
                status[] = "Song: Takt $k von $(count(>(0), seq)) · Pattern $pt   (Kette: $(chain_string(eng.song.chain)))"
            end
        end
        playhead[] = pt == eng.edit_pat ? st : -1
        for t in 1:NTRACKS; refresh_row!(t); end
        refresh_patbtns!()
        if !eng.playing && last[][3]
            playbtn.label[] = "▶  Play"
        elseif eng.playing && pt == 0
            status[] = "Einzähler …"
        end
        last[] = cur
        return
    end
    return fig, eng, tick!
end
