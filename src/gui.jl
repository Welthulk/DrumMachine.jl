# GLMakie GUI: step grid, transport, patterns/chain, save/load, WAV export.

using GLMakie

const SONG_DIR = normpath(joinpath(@__DIR__, "..", "songs"))     # example songs shipped with the package

"""
Folder for the user's songs and WAV exports: the package's `songs/` in a writable checkout (git
clone), otherwise (package installed with Pkg, read-only) `~/.local/share/DrumMachine/songs`.
`DRUMMACHINE_SONG_DIR` overrides it.
"""
function song_dir()
    d = get(ENV, "DRUMMACHINE_SONG_DIR", "")
    if isempty(d)
        d = dir_writable(SONG_DIR) ? SONG_DIR : joinpath(data_dir(), "songs")
    end
    mkpath(d)
    return d
end

"True if files can be created in `dir`."
function dir_writable(dir)
    isdir(dir) || return false
    probe = joinpath(dir, ".write_test_$(getpid())")
    try
        touch(probe); rm(probe)
        return true
    catch
        return false
    end
end

"Path of song `name`: the user's folder first, then the example songs."
function song_file(name::AbstractString)
    for d in unique([song_dir(), SONG_DIR])
        f = joinpath(d, name * ".toml")
        isfile(f) && return f
    end
    return joinpath(song_dir(), name * ".toml")
end

# Color palette (dark)
const C_BG      = Makie.to_color("#121418")     # window background
const C_PANEL   = Makie.to_color("#1b1e24")     # panels
const C_LINE    = Makie.to_color("#2c313a")     # panel borders, separators
const C_TEXT    = Makie.to_color("#e3e6eb")
const C_TEXT2   = Makie.to_color("#8c94a0")     # secondary text
const C_DIM     = Makie.to_color("#4a505b")     # inactive labels
const C_OFF_A   = Makie.to_color("#2b3038")     # step off, beat 1/3/…
const C_OFF_B   = Makie.to_color("#23272e")     # step off, beat 2/4/…
const C_HEAD    = Makie.to_color("#33547c")     # playhead on an empty step
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

"Sets a toggle only if its value changes (otherwise the display flips)."
set_toggle!(t, v::Bool) = (t.active[] == v || (t.active[] = v); t)

"Background panel for one row of the main layout."
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
  BPM                   Regler oder Zahl eintippen (30–400)
  GC-Pause              Speicherbereinigung beim Abspielen bis zu x min anhalten
                        (gegen Knackser bei schnellen Tempi), läuft bei Stop, nach Ablauf
                        der Zeit oder unter 1 GB freiem Speicher wieder; beim Ablauf mitten
                        im Spielen ist ein einzelner Knackser möglich

RASTER & SWING
  Raster                16tel, 8tel-Triolen, 16tel-Triolen oder 8tel
  Swing                 Lage der Off-Beat-Note: 50 % gerade, 67 % Triole, 75 % punktiert
  Auto / 8tel / 16tel   worauf im geraden Raster geswingt wird

PATTERNS & KETTE
  1 … 16                Pattern bearbeiten   + Kopie / + Leer / Löschen / Leeren
  + Fill                neues Pattern: Groove mit Fill am Ende, nochmal klicken = anderer Fill
  Steps                 Länge des Patterns (z. B. 12 für 3/4, 20 für 5/4)
  Kette                 Reihenfolge für Song-Modus und Export, z. B. „1x3 2“ = 1 1 1 2

WAV-EDITOR, METRONOM & DOCS
  WAV-Editor            exportierte WAVs schneiden, Fades, Effekte, Einzähler (eigenes Fenster)
  Docs                  Dokumentation: Song-Dateiformat, WAV-Editor, Metronom
  Metronom              Klick mit Taktart, Unterteilung, Betonung, Klang, Lücken- und Tempo-Trainer

DATEI
  Neu / Duplizieren     neuer Groove bzw. Kopie, das Original bleibt erhalten
  Speichern             songs/<Name>.toml – vorhandene Dateien erst nach zweitem Klick
  Bearbeiten            an: „Speichern“ überschreibt die geladene Datei ohne Rückfrage
  Preset / Song laden   Groove-Bibliothek bzw. eigene Songs
  Datei öffnen …        Song (.toml) aus einem beliebigen Verzeichnis laden
  JSON-Import …         Kompositionen aus Browser-Drum-Machines (Drum-JSON) als Songs übernehmen,
                        mehrere Dateien auf einmal; Strg+V importiert aus der Zwischenablage

EXPORT
  Wiederholungen        wie oft die Kette hintereinander geschrieben wird
  Einzähler, Klick      Takte vorweg bzw. Metronom auf jedem Schlag
  Stereo | Mono         wirkt auf Wiedergabe und WAV
  L ⇄ R                 linken und rechten Kanal tauschen (Wiedergabe und WAV)
  Loop                  nahtlose Schleife ohne Einzähler, Datei „<Name> Loop.wav“;
                        am TD-27: SONG → [F2] SETUP → Loop Type = LOOP
  WAV exportieren       songs/<Name>.wav, 44,1 kHz, 16 Bit
"""

# English quick help (labels as shown in the English GUI).
const HELP_TEXT_EN = """
INPUT
  Left click            note on / off
  Right click           ghost  →  normal  →  accent
  Track name            preview      M / S   mute / solo (also applies to the export)
  Track effects         click a track name: EQ (low, mid, high) and
                        chorus / flanger for this track, saved with the song

TRANSPORT
  Space                 play / stop
  Mode: Pattern         loops the pattern shown in the grid
  Mode: Song            loops the chain, the grid follows the playing pattern
  Count-in              count-in bar(s) before playback starts
  BPM                   slider, or type a number (30–400)
  GC pause              halt garbage collection during playback for up to x min
                        (against crackles at fast tempos), resumes on stop, when the time
                        is up or below 1 GB of free memory; if the time runs out while
                        playing, a single crackle is possible

GRID & SWING
  Grid                  16ths, 8th triplets, 16th triplets or 8ths
  Swing                 position of the off-beat: 50 % straight, 67 % triplet, 75 % dotted
  Auto / 8ths / 16ths   which subdivision swings in a straight grid

PATTERNS & CHAIN
  1 … 16                edit pattern
  + Copy / + Empty      new pattern as copy / empty
  Delete / Clear        delete pattern / clear all notes
  + Fill                new pattern: groove with a fill at the end, click again = other fill
  Steps                 pattern length (e.g. 12 for 3/4, 20 for 5/4)
  Chain                 order for song mode and export, e.g. “1x3 2” = 1 1 1 2

WAV EDITOR, METRONOME & DOCS
  WAV Editor            cut exported WAVs, fades, effects, count-in (own window)
  Docs                  documentation: song file format, WAV editor, metronome
  Metronome             click with time signature, subdivision, accents, sound, gap and tempo trainer

FILE
  New / Duplicate       new groove or copy, the original stays untouched
  Save                  songs/<name>.toml – existing files only after a second click
  Edit                  on: “Save” overwrites the loaded file without asking
  Load preset / song    groove library or your own songs
  Open file …           load a song (.toml) from any folder
  JSON import …         take over compositions from browser drum machines (Drum-JSON) as songs,
                        several files at once; Ctrl+V imports from the clipboard

EXPORT
  Repeats               how many times the chain is written
  Count-in, Click       count-in bars and metronome on every beat
  Stereo | Mono         applies to playback and WAV
  L ⇄ R                 swap left and right channel (playback and WAV)
  Loop                  seamless loop without count-in, file “<name> Loop.wav”;
                        on the TD-27: SONG → [F2] SETUP → Loop Type = LOOP
  Export WAV            songs/<name>.wav, 44.1 kHz, 16 bit
"""

"Text of the info window (German / English)."
function info_text(lang::Symbol = LANG[])
    v = "DrumMachine.jl  " * app_version()
    lang == :en ? """
$v
Step sequencer for drum practice: enter grooves, preview them, export WAVs.
With metronome, WAV editor and Drum-JSON import.

Code: MIT license          $(REPO_URL)

KITS
  BlackPearl         AVL Drumkits (bandshed.net)                        CC BY-SA 3.0
  CrocellKit         DrumGizmo, stereo mix by Henry Järvinen            CC BY 4.0
  VirtuosityDrums    Versilian Studios / Karoryfer                      CC0
  RedZeppelin, BlondeBop, BlondeBopHotRods, BuskmansHoliday
                     AVL Drumkits (bandshed.net)                        CC BY-SA 3.0
  DRSKit, MuldjordKit, Aasimonster, ShittyKit, Sommerhack
                     DrumGizmo (drumgizmo.org), stereo mix by us        CC BY 4.0
  CrocellClose/Studio/Room/Vintage/LoFi
                     CrocellKit (DrumGizmo), own mixes of the mics      CC BY 4.0
  808 / 909          synthesized

GREETINGS
  Greetings to OneMotion (onemotion.com/drum-machine), a fine drum machine
  in the browser. Compositions saved there (JSON) can be taken over here
  with "JSON import".
  DrumMachine.jl is an independent project and not affiliated with OneMotion.

  Thanks to the Julia and Makie communities
  (GLMakie, PortAudio.jl, WAV.jl, JSON.jl).
""" : """
$v
Step-Sequencer zum Schlagzeug-Üben: Grooves eintragen, vorhören, als WAV exportieren.
Mit Metronom, WAV-Editor und Drum-JSON-Import.

Code: MIT-Lizenz           $(REPO_URL)

KITS
  BlackPearl         AVL Drumkits (bandshed.net)                        CC BY-SA 3.0
  CrocellKit         DrumGizmo, Stereo-Mix von Henry Järvinen           CC BY 4.0
  VirtuosityDrums    Versilian Studios / Karoryfer                      CC0
  RedZeppelin, BlondeBop, BlondeBopHotRods, BuskmansHoliday
                     AVL Drumkits (bandshed.net)                        CC BY-SA 3.0
  DRSKit, MuldjordKit, Aasimonster, ShittyKit, Sommerhack
                     DrumGizmo (drumgizmo.org), Stereo-Mix von uns      CC BY 4.0
  CrocellClose/Studio/Room/Vintage/LoFi
                     CrocellKit (DrumGizmo), eigene Mischungen          CC BY 4.0
  808 / 909          synthetisiert

GRÜSSE
  Ein Gruß an OneMotion (onemotion.com/drum-machine), eine feine Drum-Machine
  im Browser. Dort gespeicherte Kompositionen (JSON) lassen sich hier über
  „JSON-Import“ übernehmen.
  DrumMachine.jl ist ein unabhängiges Projekt und nicht mit OneMotion verbunden.

  Dank an die Julia- und Makie-Gemeinschaft
  (GLMakie, PortAudio.jl, WAV.jl, JSON.jl).
"""
end

"Opens the info window (version, licenses, greetings)."
function show_info()
    fig = with_theme(DM_THEME) do
        f = Figure(size = (820, 560), figure_padding = 16)
        panel!(f[1, 1])
        Label(f[1, 1], info_text(); font = "DejaVu Sans Mono", fontsize = 13, justification = :left,
              halign = :left, valign = :top, color = C_TEXT, padding = (22, 22, 20, 20),
              tellwidth = false, tellheight = false)
        gh = Button(f[2, 1], label = "GitHub ↗", halign = :left, tellwidth = false)
        on(_ -> open_url(REPO_URL), gh.clicks)
        f
    end
    screen = display(GLMakie.Screen(; title = L("DrumMachine – Info")), fig)
    set_icon!(screen)
    return screen
end

"Figure with the quick help, switchable between German and English."
help_figure(lang::Symbol = LANG[]) = with_theme(DM_THEME) do
    f = Figure(size = (920, 990), figure_padding = 16)     # longest line ~100 chars, 54 lines
    bar = f[1, 1] = GridLayout(halign = :left, tellwidth = false)
    de = Button(bar[1, 1], label = "Deutsch", width = 90)
    en = Button(bar[1, 2], label = "English", width = 90)
    Label(bar[1, 3], "DrumMachine.jl $(app_version())  ·  $(REPO_URL)", color = C_TEXT2, fontsize = 12,
          padding = (14, 0, 0, 0))
    panel!(f[2, 1])
    txt = Observable(lang == :en ? HELP_TEXT_EN : HELP_TEXT)
    Label(f[2, 1], txt; font = "DejaVu Sans Mono", fontsize = 13, justification = :left,
          halign = :left, valign = :top, color = C_TEXT, padding = (22, 22, 20, 20),
          tellwidth = false, tellheight = false)
    function mark(l)
        de.buttoncolor[] = l == :de ? C_ACTIVE : C_BTN; de.labelcolor[] = l == :de ? C_BG : C_TEXT
        en.buttoncolor[] = l == :en ? C_ACTIVE : C_BTN; en.labelcolor[] = l == :en ? C_BG : C_TEXT
    end
    mark(lang)
    on(_ -> (txt[] = HELP_TEXT; mark(:de)), de.clicks)
    on(_ -> (txt[] = HELP_TEXT_EN; mark(:en)), en.clicks)
    rowsize!(f.layout, 1, Fixed(36))
    f
end

"Opens a window with the quick help."
function show_help()
    screen = display(GLMakie.Screen(; title = L("DrumMachine – Hilfe")), help_figure())
    set_icon!(screen)
    return screen
end

const REPO_URL = "https://github.com/Welthulk/DrumMachine.jl"
const ICON_DIR = normpath(joinpath(@__DIR__, "..", "assets", "icon"))

"Version from Project.toml, e.g. \"v0.6.1\"."
app_version() = "v" * string(something(pkgversion(@__MODULE__), v"0.0.0"))

"Sets the practice-pad icon (assets/icon) as the window icon. May have no effect on macOS/Wayland."
function set_icon!(screen)
    try
        files = filter(endswith(".png"), readdir(ICON_DIR; join = true))
        isempty(files) && return
        GLMakie.GLFW.SetWindowIcon(screen.glscreen, map(GLMakie.Makie.load_icon, files))
    catch e
        @debug "Window icon not set" exception = e
    end
    return
end

"Opens `url` in the default browser."
function open_url(url::AbstractString)
    cmd = Sys.isapple() ? `open $url` : Sys.iswindows() ? `cmd /c start "" $url` : `xdg-open $url`
    try
        Base.run(pipeline(cmd; stdout = devnull, stderr = devnull); wait = false)
        return true
    catch
        return false
    end
end

const RASTER_OPTS = [("16tel (4 pro Schlag)", 4), ("Triolen (3 pro Schlag)", 3),   # i18n-ok: shown via Ls()
                     ("16tel-Triolen (6 pro Schlag)", 6), ("8tel (2 pro Schlag)", 2)]   # i18n-ok: shown via Ls()
const SWING_OPTS = [("Auto", 0), ("auf 8tel", 8), ("auf 16tel", 16)]   # i18n-ok: shown via Ls()
const STEP_OPTS = [3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 15, 16, 18, 20, 21, 24, 28, 30, 32]
const MAXPATTERNS = 16

"Count syllables for the header row: 1 e + a / 1 + a / 1 la li + la li / 1 +."
function count_labels(steps::Int, spb::Int)
    syl = spb == 4 ? ("", "e", "+", "a") : spb == 3 ? ("", "+", "a") : spb == 6 ? ("", "la", "li", "+", "la", "li") :
          spb == 2 ? ("", "+") : ntuple(_ -> "", spb)
    [((s - 1) % spb == 0 ? string((s - 1) ÷ spb + 1) : syl[(s-1)%spb+1]) for s in 1:steps]
end

"""
    pick_file(startdir; title, ext, kind, save = false, name = "") -> String or nothing

Opens the system file dialog (zenity or kdialog) for files with extension `ext` (e.g. "toml",
"wav"; `kind` is the label shown for the filter). With `save = true` it asks for a file name to
save to (`name` is the suggestion, zenity also confirms overwriting). Returns the chosen path,
`""` on cancel, or `nothing` if no dialog program is installed. Blocks only the calling task,
the GUI keeps running.
"""
function pick_file(startdir::AbstractString; title::AbstractString, ext::AbstractString,
                   kind::AbstractString, save::Bool = false, name::AbstractString = "")
    dir = isdir(startdir) ? startdir : homedir()
    start = joinpath(dir, name)
    cmd = if Sys.which("zenity") !== nothing
        args = ["zenity", "--file-selection", "--title=$title", "--filename=$start",
                "--file-filter=$kind (*.$ext) | *.$ext", "--file-filter=$(L("Alle Dateien")) | *"]
        save && append!(args, ["--save", "--confirm-overwrite"])
        Cmd(args)
    elseif Sys.which("kdialog") !== nothing
        Cmd(["kdialog", "--title", title, save ? "--getsavefilename" : "--getopenfilename", start,
             "*.$ext|$kind (*.$ext)"])
    else
        return nothing
    end
    out = IOBuffer()
    p = Base.run(pipeline(ignorestatus(cmd); stdout = out, stderr = devnull))   # `run` is the GUI here
    success(p) || return ""                       # cancel
    return strip(String(take!(out)))
end

"""
    pick_files(startdir; title, exts, kind) -> Vector{String} or nothing

File dialog for several files with one of the extensions `exts`. Empty on cancel, `nothing` if
no dialog program is installed.
"""
function pick_files(startdir::AbstractString; title::AbstractString, exts, kind::AbstractString)
    dir = isdir(startdir) ? startdir : homedir()
    pat = join(("*.$e" for e in exts), " ")
    cmd = if Sys.which("zenity") !== nothing
        Cmd(["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=$title",
             "--filename=$(dir)/", "--file-filter=$kind ($pat) | $pat", "--file-filter=$(L("Alle Dateien")) | *"])
    elseif Sys.which("kdialog") !== nothing
        Cmd(["kdialog", "--title", title, "--multiple", "--separate-output", "--getopenfilename", dir,
             "$pat|$kind ($pat)"])
    else
        return nothing
    end
    out = IOBuffer()
    p = Base.run(pipeline(ignorestatus(cmd); stdout = out, stderr = devnull))
    success(p) || return String[]
    return filter(!isempty, strip.(split(String(take!(out)), r"\n|\\n")))
end

"Text in the clipboard (GLFW of the window, else wl-paste / xclip), \"\" if not available."
function clipboard_text(screen)
    try
        screen === nothing || return GLMakie.GLFW.GetClipboardString(screen.glscreen)
    catch
    end
    for cmd in (`wl-paste --no-newline`, `xclip -selection clipboard -o`)
        Sys.which(cmd.exec[1]) === nothing && continue
        try
            return read(pipeline(cmd; stderr = devnull), String)
        catch
        end
    end
    return ""
end

"File dialog for loading a song (.toml)."
pick_song_file(startdir::AbstractString = song_dir()) =
    pick_file(startdir; title = L("Song laden"), ext = "toml", kind = "Songs")

function list_songs()
    names = String[]
    for d in unique([song_dir(), SONG_DIR])     # own songs and the example songs
        isdir(d) || continue
        append!(names, splitext(f)[1] for f in readdir(d) if endswith(f, ".toml"))
    end
    sort(unique(names))
end

"Short summary for the status line, e.g. `100 BPM · Swing 63 % (Auto) · Kette 1 1 2`."
function song_summary(s::Song)
    pct = round(Int, 100s.swing)
    sw = s.steps_per_beat in (3, 6) ? (s.swing == 2 / 3 ? L("exakte Triolen") : L("Triolen-Swing {1} %", pct)) :
         s.swing == 0.5 ? L("kein Swing") :
         L("Swing {1} % ({2})", pct, s.swing_on == 0 ? L("Auto") : L("auf {1}tel", s.swing_on))
    return L("{1} BPM · {2} · Kette {3}", round(Int, s.bpm), sw, chain_string(s.chain))
end

fmt_time(sec) = string(floor(Int, sec ÷ 60), ":", lpad(round(Int, sec % 60) % 60, 2, '0'))

"""
    run(; song = nothing, block = true)

Starts the drum machine. Without `song` it continues with the song and state of the last session
(see `load_session`), on the very first start with the preset "Rock: 8tel". `block=false` returns
immediately (for the REPL) and returns `(fig, eng)`.
"""
function run(; song::Union{Song,Nothing} = nothing, block::Bool = true, audio::Bool = true)
    GLMakie.activate!(title = "DrumMachine.jl")
    set_lang!(initial_lang())
    session = new_session()
    if song === nothing                                    # continue where the last session ended
        last = load_session()
        session.restore[] = last
        song = last === nothing ? preset("Rock: 8tel") : last.song
    end
    gcpause_set!(gcpause_setting())
    fig, eng, tick! = build_gui(song; audio, session)
    screen = display(fig)
    session.screen[] = screen
    set_icon!(screen)
    cur_tick = Ref{Function}(tick!)
    # switching the language rebuilds the window with the same engine (song and playback stay)
    session.rebuild[] = () -> begin
        newfig, _, newtick! = build_gui(eng.song; eng, session)
        display(screen, newfig)
        cur_tick[] = newtick!
        fig = newfig
    end
    # first start: build missing sample kits in the background (messages go through the session)
    post(msg) = (isready(session.kitmsg) && length(session.kitmsg.data) > 32) || put!(session.kitmsg, msg)
    auto_fetch_kits!(post, _ -> (session.kits_changed[] = true))
    # playhead display (runs on the main thread)
    @async begin
        n = 0
        while isopen(screen)
            cur_tick[]()
            (n += 1) % 1800 == 0 && save_session(eng, session)    # every ~30 s, only if changed
            sleep(1 / 60)
        end
        save_session(eng, session)
        gcpause_release!()
        stop_audio!(eng)
    end
    if block
        wait(screen)
        save_session(eng, session)
        return nothing
    end
    return fig, eng
end

"Tempo typed into the BPM field: a number in the slider's range 30–400 (decimals are rounded)."
parse_bpm(str) = round(Int, parse(Float64, replace(strip(str), ',' => '.')))
valid_bpm(str) = (v = tryparse(Float64, replace(strip(str), ',' => '.'));
                  v !== nothing && isfinite(v) && 30 <= round(Int, v) <= 400)

"Sets observable `o` to `v` only if the value differs (avoids needless Makie updates)."
set_if_changed!(o, v) = (o[] == v || (o[] = v); o)

"Axis options without ticks, labels, grid and spines (faster than `hidedecorations!` afterwards)."
const BARE_AXIS = (xticksvisible = false, yticksvisible = false, xticklabelsvisible = false,
                   yticklabelsvisible = false, xgridvisible = false, ygridvisible = false,
                   xminorgridvisible = false, yminorgridvisible = false, xminorticksvisible = false,
                   yminorticksvisible = false, xlabelvisible = false, ylabelvisible = false,
                   titlevisible = false, leftspinevisible = false, rightspinevisible = false,
                   topspinevisible = false, bottomspinevisible = false)

"""
    build_gui(song; audio=true) -> (fig, eng, tick!)

Builds the figure and engine (without a window). `tick!()` updates the playhead and display.
"""
build_gui(song::Song; audio::Bool = true, eng = nothing, session = new_session()) =
    with_theme(() -> _build_gui(song; audio, eng, session), DM_THEME)

"""
State that outlives a rebuild of the main window (language switch): last WAV export, the open
editor window and the rebuild callback set by `run`.
"""
new_session() = (last_export = Ref(""), wave_win = Ref{Any}(nothing), rebuild = Ref{Any}(nothing),
                 metro_win = Ref{Any}(nothing), screen = Ref{Any}(nothing),
                 kitmsg = Channel{String}(64),            # messages of the background kit download
                 kits_changed = Threads.Atomic{Bool}(false),
                 edit_path = Ref(""), edit_name = Ref(""),  # edit mode ("Bearbeiten"): file and its song name
                 edit_on = Ref(false),                    # the toggle itself (may be off with a file loaded)
                 restore = Ref{Any}(nothing))             # state of the last session, applied once at start

# ---------------------------------------------------------------------------
# Last session: song and GUI state are stored on exit (and every 30 s while they change) and
# loaded on the next start.
# ---------------------------------------------------------------------------

"File with the song of the last session (next to the settings file)."
last_song_path() = joinpath(dirname(settings_path()), "last_song.toml")

const SESSION_LOCK = ReentrantLock()
const SESSION_SAVED = Ref("")                             # state written last (skip unchanged saves)

"GUI state that is not part of the song (stored in the settings as `[session]`)."
session_state(eng, session) = Dict{String,Any}("edit_path" => session.edit_path[], "edit_name" => session.edit_name[],
                                               "edit_on" => session.edit_on[], "edit_pat" => eng.edit_pat,
                                               "songmode" => eng.songmode)

"""
    save_session(eng, session; force = false) -> Bool

Writes the current song to `last_song.toml` and the GUI state to the settings, if anything changed
since the last save (or `force`). The song file is replaced atomically.
"""
function save_session(eng, session; force::Bool = false)
    lock(SESSION_LOCK) do
        song = sprint(io -> TOML.print(io, song_to_dict(eng.song); sorted = true))
        st = session_state(eng, session)
        key = song * repr(sort(collect(st); by = first))
        (force || key != SESSION_SAVED[]) || return false
        try
            p = last_song_path()
            mkpath(dirname(p))
            tmp = p * ".tmp"
            write(tmp, song)
            mv(tmp, p; force = true)
            save_setting!("session", st)
            SESSION_SAVED[] = key
            return true
        catch e
            @warn L("Sitzung konnte nicht gespeichert werden") exception = e
            return false
        end
    end
end

"""
    load_session() -> NamedTuple or nothing

Song and GUI state of the last session; `nothing` if there is none or it cannot be read. A file
being edited that no longer exists is dropped (edit mode off).
"""
function load_session()
    p = last_song_path()
    isfile(p) || return nothing
    song = try
        load_song(p)
    catch e
        @warn L("Letzte Sitzung konnte nicht geladen werden") exception = e
        return nothing
    end
    d = get(load_settings(), "session", Dict{String,Any}())
    d isa AbstractDict || (d = Dict{String,Any}())
    path = string(get(d, "edit_path", ""))
    isfile(path) || (path = "")
    pat = get(d, "edit_pat", 1)
    return (song = song, edit_path = path, edit_name = path == "" ? "" : string(get(d, "edit_name", "")),
            edit_on = path != "" && get(d, "edit_on", false) === true,
            edit_pat = pat isa Integer ? clamp(Int(pat), 1, length(song.patterns)) : 1,
            songmode = get(d, "songmode", false) === true)
end

function _build_gui(song::Song; audio::Bool = true, eng = nothing, session = new_session())
    kits = kit_entries()                                  # samples are loaded on selection
    kitnames = [k.name for k in kits]
    dlkits = on_demand_kits()                             # large kits, downloaded when chosen
    kit_options() = vcat(kitnames, [L("{1} (laden, {2})", k[1], k[2]) for k in dlkits])
    kitidx = something(findfirst(==(song.kit), kitnames), 1)
    if eng === nothing
        eng = Engine(song, get_kit(kits[kitidx]))
        eng.song.kit = kitnames[kitidx]
        r = session.restore[]
        if r !== nothing
            eng.edit_pat = r.edit_pat
            eng.songmode = r.songmode
            session.edit_path[] = r.edit_path
            session.edit_name[] = r.edit_name
            session.edit_on[] = r.edit_on
        end
        audio && start_audio!(eng)
    end

    fig = Figure(size = (1320, 975), backgroundcolor = C_BG, fontsize = 14, figure_padding = 18)
    HELP = L("Bereit.  Linksklick: Schlag an/aus · Rechtsklick: Ghost → normal → Akzent · Leertaste: Play/Stop · ? = Hilfe")
    status = Observable(HELP)

    # ---------------------------------------------------------------- Header
    hdr = fig[1, 1] = GridLayout(tellwidth = false, halign = :left)
    Label(hdr[1, 1], "DRUM MACHINE", font = :bold, fontsize = 22, color = C_TEXT)
    Label(hdr[1, 2], L("Groove  ·  Vorhören  ·  WAV-Export"), fontsize = 14, color = C_TEXT2, padding = (14, 0, 0, 0))
    hdr_r = fig[1, 1] = GridLayout(tellwidth = false, halign = :right)
    Label(hdr_r[1, 1], app_version(), fontsize = 13, color = C_TEXT2, padding = (0, 8, 0, 0))
    ghbtn = Button(hdr_r[1, 2], label = "GitHub ↗", height = 34, fontsize = 13)
    metbtn = Button(hdr_r[1, 3], label = L("Metronom"), height = 34, fontsize = 13)
    wavbtn = Button(hdr_r[1, 4], label = L("WAV-Editor"), height = 34, fontsize = 13)
    docsbtn = Button(hdr_r[1, 5], label = "Docs", height = 34, fontsize = 13)
    infobtn = Button(hdr_r[1, 6], label = "Info", height = 34, fontsize = 13)
    helpbtn = Button(hdr_r[1, 7], label = "?", width = 34, height = 34, cornerradius = 17,
                     fontsize = 17, font = :bold)
    langbtns = [Button(hdr_r[1, 7+k], label = uppercase(String(l)), width = 40, height = 34, fontsize = 13,
                       buttoncolor = LANG[] == l ? C_ACTIVE : C_BTN, labelcolor = LANG[] == l ? C_BG : C_TEXT)
                for (k, l) in enumerate(LANGS)]
    for (b, l) in zip(langbtns, LANGS)
        on(b.clicks) do _
            LANG[] == l && return
            set_lang!(l; persist = true)
            rb = session.rebuild[]
            if rb === nothing
                status[] = L("Sprache wird beim nächsten Öffnen übernommen.")
            else
                status[] = L("Sprache wird umgestellt …")
                @async (sleep(0.05); rb())              # let the message show first
            end
        end
    end

    # ---------------------------------------------------------------- Transport
    panel!(fig[2, 1])
    tbox = fig[2, 1] = GridLayout(tellwidth = false, halign = :left, alignmode = Outside(14))
    top = tbox[1, 1] = GridLayout(halign = :left)
    playbtn = Button(top[1, 1], label = "▶  Play", width = 100, buttoncolor = C_ACTIVE, labelcolor = C_BG,
                     buttoncolor_hover = C_LEVEL_H[2], labelcolor_hover = C_BG, labelcolor_active = C_BG,
                     font = :bold)
    modebtn = Button(top[1, 2], label = eng.songmode ? L("Modus: Song") : L("Modus: Pattern"), width = 140)
    Label(top[1, 3], L("Einzähler"), halign = :right, color = C_TEXT2)
    ci_toggle = Toggle(top[1, 4], active = false)
    Label(top[1, 5], "BPM", halign = :right, color = C_TEXT2)
    bpm_sl = Slider(top[1, 6], range = 30:1:400, startvalue = song.bpm, width = 160)
    bpm_tb = Textbox(top[1, 7], stored_string = string(round(Int, song.bpm)), width = 50,
                     validator = valid_bpm, reset_on_defocus = false)
    Label(top[1, 8], "Swing", halign = :right, color = C_TEXT2)
    sw_sl = Slider(top[1, 9], range = 50:1:75, startvalue = round(Int, 100song.swing), width = 110)
    sw_lab = Label(top[1, 10], "", width = 40, font = :bold)
    sw_opts = Ls(first.(SWING_OPTS))                # displayed options, mapped back by index
    sw_menu = Menu(top[1, 11], options = sw_opts, width = 95)
    Label(top[1, 12], L("   GC-Pause"), halign = :right, color = C_TEXT2)
    gc_opts = [m == 0 ? L("aus") : "$m min" for m in GC_PAUSE_OPTS]
    gc_menu = Menu(top[1, 13], options = gc_opts, width = 80,
                   default = gc_opts[something(findfirst(==(GCPAUSE.minutes), GC_PAUSE_OPTS), 1)])

    top2 = tbox[2, 1] = GridLayout(halign = :left)
    Label(top2[1, 1], L("Raster"), halign = :right, color = C_TEXT2)
    raster_opts = Ls(first.(RASTER_OPTS))
    raster_menu = Menu(top2[1, 2], options = raster_opts, width = 225)
    Label(top2[1, 3], "Kit", halign = :right, color = C_TEXT2)
    kit_menu = Menu(top2[1, 4], options = kit_options(), default = kitnames[kitidx], width = 150)
    Label(top2[1, 5], "Gain", halign = :right, color = C_TEXT2)
    kg_sl = Slider(top2[1, 6], range = 0:0.01:2, startvalue = eng.kitgain, width = 80)
    Label(top2[1, 7], "FX", halign = :right, color = C_TEXT2)
    fx_menu = Menu(top2[1, 8], options = FX_NAMES, default = song.fx, width = 90)
    Label(top2[1, 9], L("Anteil"), halign = :right, color = C_TEXT2)
    fx_sl = Slider(top2[1, 10], range = 0:0.01:1, startvalue = song.fxmix, width = 100)
    Label(top2[1, 11], "Master", halign = :right, color = C_TEXT2)
    mst_sl = Slider(top2[1, 12], range = 0:0.01:1.5, startvalue = song.master, width = 100)
    rowgap!(tbox, 10)

    # ---------------------------------------------------------------- Patterns
    panel!(fig[3, 1])
    pbox = fig[3, 1] = GridLayout(tellwidth = false, halign = :left, alignmode = Outside(14))
    pbar = pbox[1, 1] = GridLayout(halign = :left)
    Label(pbar[1, 1], "PATTERN", font = :bold, color = C_TEXT2, width = 70, halign = :left)
    patbtns = [Button(pbar[1, 1+i], label = string(i), width = 36) for i in 1:MAXPATTERNS]
    addcopy = Button(pbar[1, MAXPATTERNS+2], label = L("+ Kopie"))
    addempty = Button(pbar[1, MAXPATTERNS+3], label = L("+ Leer"))
    fillbtn = Button(pbar[1, MAXPATTERNS+4], label = "+ Fill")
    delbtn = Button(pbar[1, MAXPATTERNS+5], label = L("Löschen"))
    clrbtn = Button(pbar[1, MAXPATTERNS+6], label = L("Leeren"))
    colgap!(pbar, 6)
    colgap!(pbar, MAXPATTERNS + 1, 16)       # gap between pattern numbers and actions
    pbar2 = pbox[2, 1] = GridLayout(halign = :left)
    Label(pbar2[1, 1], "Steps", halign = :left, color = C_TEXT2, width = 70)
    steps_menu = Menu(pbar2[1, 2], options = string.(STEP_OPTS), width = 60)
    Label(pbar2[1, 3], L("Kette"), halign = :right, color = C_TEXT2)
    chain_tb = Textbox(pbar2[1, 4], stored_string = chain_string(song.chain), width = 260,
                       placeholder = L("z. B. 1x3 2"), reset_on_defocus = false)
    Label(pbar2[1, 5], L("für Song-Modus und Export"), color = C_DIM, fontsize = 12)
    rowgap!(pbox, 10)

    # ---------------------------------------------------------------- Grid
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
    fx_track = Ref(1)                          # track whose effects are shown on the right
    for t in 1:NTRACKS
        r = t + 1
        nb = Button(grid[r, 1], label = L(TRACKS[t][2]), width = 100)
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
        ax = Axis(grid[r, 5]; height = 34, backgroundcolor = :transparent,
                  xrectzoom = false, yrectzoom = false, xzoomlock = true, yzoomlock = true,
                  xpanlock = true, ypanlock = true, BARE_AXIS...)
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
    leg = Label(grid[NTRACKS+2, 5], L("Ghost (o)  ·  normal (x)  ·  Akzent (X)     Klick auf den Spurnamen = Vorhören + Effekte"),
                halign = :left, color = C_TEXT2, fontsize = 12, tellwidth = false)

    # track effects (right of the grid): EQ + chorus/flanger of the selected track
    fxbox = grid[1:NTRACKS+2, 6] = GridLayout(valign = :top, halign = :left)
    Label(fxbox[1, 1:3], L("SPUR-EFFEKTE"), font = :bold, color = C_TEXT2, halign = :left)
    fx_title = Label(fxbox[2, 1:3], "", font = :bold, color = C_ACTIVE, halign = :left, fontsize = 16)
    fx_sliders = Dict{Symbol,Slider}()
    fx_vals = Dict{Symbol,Observable{String}}()
    midf_range = [200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6000]   # third-octave steps
    rate_range = vcat(0.05:0.05:1, 1.1:0.1:5)
    fx_rows = [(:eq_low, L("Tiefen"), -12:0.5:12, v -> "$(v) dB"),
               (:eq_mid, L("Mitten"), -12:0.5:12, v -> "$(v) dB"),
               (:eq_midf, L("Mitten bei"), midf_range, v -> v >= 1000 ? "$(round(v / 1000, digits = 1)) kHz" : "$(round(Int, v)) Hz"),
               (:eq_high, L("Höhen"), -12:0.5:12, v -> "$(v) dB"),
               (:mod_mix, "Mix", 0:0.01:1, v -> "$(round(Int, 100v)) %"),
               (:mod_rate, "Rate", rate_range, v -> "$(round(v, digits = 2)) Hz"),
               (:mod_depth, L("Tiefe"), 0:0.01:1, v -> "$(round(Int, 100v)) %"),
               (:mod_fb, "Feedback", 0:0.01:0.9, v -> "$(round(Int, 100v)) %")]
    Label(fxbox[3, 1:3], "EQ", color = C_DIM, fontsize = 12, halign = :left)
    Label(fxbox[8, 1], L("Effekt"), color = C_TEXT2, halign = :left)
    mod_opts = Ls(MOD_NAMES)                        # display only, the song stores MOD_NAMES
    mod_menu = Menu(fxbox[8, 2:3], options = mod_opts, default = mod_opts[1], width = 150)
    for (k, (f, name, rng, fmt)) in enumerate(fx_rows)
        row = k <= 4 ? 3 + k : 4 + k
        Label(fxbox[row, 1], name, color = C_TEXT2, halign = :left)
        sl = Slider(fxbox[row, 2], range = rng, startvalue = getfield(TrackParams(), f), width = 130)
        val = Observable("")
        Label(fxbox[row, 3], val, color = C_TEXT, halign = :left, width = 62, fontsize = 12)
        on(v -> (val[] = fmt(v)), sl.value; update = true)
        fx_sliders[f] = sl; fx_vals[f] = val
    end
    fx_reset = Button(fxbox[13, 1:3], label = L("Effekte der Spur zurücksetzen"))
    rowgap!(fxbox, 4); colgap!(fxbox, 6)

    # ---------------------------------------------------------------- File / export
    panel!(fig[5, 1])
    fbox = fig[5, 1] = GridLayout(tellwidth = false, halign = :left, alignmode = Outside(14))
    bot = fbox[1, 1] = GridLayout(halign = :left)
    Label(bot[1, 1], L("DATEI"), font = :bold, color = C_TEXT2, width = 70, halign = :left)
    newbtn = Button(bot[1, 2], label = L("Neu"))
    dupbtn = Button(bot[1, 3], label = L("Duplizieren"))
    Label(bot[1, 4], "Name", halign = :right, color = C_TEXT2)
    name_tb = Textbox(bot[1, 5], stored_string = song.name, width = 300, reset_on_defocus = false)
    savebtn = Button(bot[1, 6], label = L("Speichern"), width = 130)
    Label(bot[1, 7], "  " * L("Bearbeiten"), halign = :right, color = C_TEXT2)
    edit_toggle = Toggle(bot[1, 8], active = false)
    edit_lab = Label(bot[1, 9], "", color = C_DIM, fontsize = 12, halign = :left)
    lbox = fbox[2, 1] = GridLayout(halign = :left)
    Label(lbox[1, 1], L("LADEN"), font = :bold, color = C_TEXT2, width = 70, halign = :left)
    preset_menu = Menu(lbox[1, 2], options = PRESET_NAMES, default = nothing, prompt = L("Preset laden …"), width = 340)
    load_menu = Menu(lbox[1, 3], options = vcat(["—"], list_songs()), default = nothing, prompt = L("Eigenen Song laden …"),
                     width = 260)
    filebtn = Button(lbox[1, 4], label = L("Datei öffnen …"))
    impbtn = Button(lbox[1, 5], label = L("JSON-Import …"))
    # re-read the song list when the menu opens (files may be added outside the program)
    on(load_menu.is_open) do open
        open || return
        opts = vcat(["—"], list_songs())
        opts == load_menu.options[] || (load_menu.options[] = opts)
    end
    bot2 = fbox[3, 1] = GridLayout(halign = :left)
    Label(bot2[1, 1], "EXPORT", font = :bold, color = C_TEXT2, width = 70, halign = :left)
    Label(bot2[1, 2], L("Wiederholungen"), halign = :right, color = C_TEXT2)
    rep_tb = Textbox(bot2[1, 3], stored_string = string(song.repeats), validator = Int, width = 50,
                     reset_on_defocus = false)
    Label(bot2[1, 4], L("Einzähler (Takte)"), halign = :right, color = C_TEXT2)
    ci_menu = Menu(bot2[1, 5], options = string.(0:4), default = string(song.countin), width = 50)
    Label(bot2[1, 6], L("Klick"), halign = :right, color = C_TEXT2)
    click_toggle = Toggle(bot2[1, 7], active = song.click)
    Label(bot2[1, 8], "   Stereo", halign = :right, color = C_TEXT2)
    mono_toggle = Toggle(bot2[1, 9], active = song.mono)
    Label(bot2[1, 10], "Mono", halign = :left, color = C_TEXT2)
    Label(bot2[1, 11], "   L ⇄ R", halign = :right, color = C_TEXT2)
    swap_toggle = Toggle(bot2[1, 12], active = song.swap_lr)
    Label(bot2[1, 13], "   Loop", halign = :right, color = C_TEXT2)
    loop_toggle = Toggle(bot2[1, 14], active = song.loop)
    expbtn = Button(bot2[1, 15], label = L("WAV exportieren"), buttoncolor = C_ACTIVE, labelcolor = C_BG,
                    buttoncolor_hover = C_LEVEL_H[2], labelcolor_hover = C_BG, labelcolor_active = C_BG,
                    font = :bold)
    explab = Label(bot2[1, 16], "", color = C_TEXT2)
    rowgap!(fbox, 10)

    Label(fig[6, 1], status, halign = :left, tellwidth = false, color = C_TEXT2, fontsize = 13)
    rowgap!(fig.layout, 12)
    colsize!(fig.layout, 1, Relative(1))      # full width, everything left-aligned
    on(_ -> show_help(), helpbtn.clicks)
    on(_ -> show_docs(), docsbtn.clicks)
    on(_ -> show_info(), infobtn.clicks)
    # WAV editor: one window; opening it again loads the last export into the open window
    last_export = session.last_export
    wave_win = session.wave_win
    on(wavbtn.clicks) do _
        win = wave_win[]
        if win !== nothing && isopen(win[1])
            # never replace the open file (it may have unsaved edits); the editor has its own button
            status[] = L("WAV-Editor ist schon offen – dort „Letzten Export öffnen“ lädt den letzten Export.")
        else
            wave_win[] = show_wave_editor(eng; path = isfile(last_export[]) ? last_export[] : "", last_export)
            status[] = L("WAV-Editor geöffnet.")
        end
    end
    on(metbtn.clicks) do _
        win = session.metro_win[]
        if win !== nothing && isopen(win)
            status[] = L("Metronom ist schon offen.")
        else
            session.metro_win[] = show_metronome(eng)
            status[] = L("Metronom geöffnet.")
        end
    end
    on(ghbtn.clicks) do _
        status[] = open_url(REPO_URL) ? L("Browser geöffnet: {1}", REPO_URL) : L("Projektseite: {1}", REPO_URL)
    end

    # ================================================================ Logic
    cur_pattern() = eng.song.patterns[clamp(eng.edit_pat, 1, length(eng.song.patterns))]
    playhead = Ref(-1)

    function refresh_row!(t)
        p = cur_pattern(); spb = eng.song.steps_per_beat
        cols = rowcolors[t][]
        changed = false
        for s in 1:MAXSTEPS
            v = p.grid[t, s]
            head = (s - 1) == playhead[]
            c = v > 0 ? (head ? C_LEVEL_H[v] : C_LEVEL[v]) :
                head ? C_HEAD : (iseven((s - 1) ÷ spb) ? C_OFF_A : C_OFF_B)
            cols[s] == c && continue
            cols[s] = c; changed = true
        end
        changed && notify(rowcolors[t])
    end

    # Grid geometry (step count, raster) of the last refresh: a pattern change in song mode
    # with the same geometry only recolors the cells – axes, labels and menu stay untouched
    # (relayouting them creates a lot of garbage, and the GC pauses then stall the audio thread).
    grid_geom = Ref((0, 0))
    function refresh_grid!()
        p = cur_pattern()
        geom = (p.steps, eng.song.steps_per_beat)
        if geom != grid_geom[]
            grid_geom[] = geom
            for ax in axes
                limits!(ax, 0, p.steps, 0, 1)
            end
            limits!(headax, 0, p.steps, 0, 1)
            headtxt[] = count_labels(p.steps, eng.song.steps_per_beat)
            headpos[] = [Point2f(s - 0.5, 0.5) for s in 1:p.steps]
            k = findfirst(==(p.steps), STEP_OPTS)
            k === nothing || steps_menu.i_selected[] == k || (steps_menu.i_selected[] = k)
        end
        for t in 1:NTRACKS
            refresh_row!(t)
        end
    end

    function refresh_tracks!()
        for t in 1:NTRACKS
            tp = eng.song.tracks[t]
            mutebtns[t].buttoncolor[] = tp.mute ? C_MUTE : C_BTN
            solobtns[t].buttoncolor[] = tp.solo ? C_SOLO : C_BTN
        end
    end

    fx_updating = Ref(false)                   # sliders are currently being set from the track
    function refresh_fx!()
        t = fx_track[]
        tp = eng.song.tracks[t]
        fx_updating[] = true
        try
            fx_title.text[] = L(TRACKS[t][2])
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
        for (i, b) in enumerate(patbtns)       # only write what changed: every write relayouts the button
            set_if_changed!(b.buttoncolor, i == eng.edit_pat ? C_ACTIVE : i <= n ? C_BTN : C_PANEL)
            set_if_changed!(b.labelcolor, i == eng.edit_pat ? C_BG : i <= n ? C_TEXT : C_DIM)
            set_if_changed!(b.label, i == playing ? "▸$i" : string(i))
        end
    end

    function refresh_export_info!()
        s = eng.song
        explab.text[] = (s.loop ? "Loop " : "") * "≈ $(fmt_time(song_seconds(s))) min"
    end

    # reset all widgets from `eng.song` (after loading a song or preset)
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
        # Set a toggle only on a real change: otherwise Makie's Toggle animates a switch
        # and then shows the wrong state.
        set_toggle!(click_toggle, s.click)
        set_toggle!(mono_toggle, s.mono)
        set_toggle!(swap_toggle, s.swap_lr)
        set_toggle!(loop_toggle, s.loop)
        k = findfirst(==(s.kit), kitnames)
        k !== nothing && (kit_menu.i_selected[] = k)
        refresh_tracks!(); refresh_grid!(); refresh_patbtns!(); refresh_export_info!(); refresh_fx!(); show_kitgain!()
    end

    song_path(name) = joinpath(song_dir(), safe_song_name(name) * ".toml")
    # first free name: `base`, `base 2`, `base 3`, …
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
        savebtn.label[] = L("Speichern")
        savebtn.buttoncolor[] = C_BTN
        savebtn.labelcolor[] = C_TEXT
    end

    function set_song!(s::Song)
        cancel_overwrite!()
        was = eng.playing
        was && stop!(eng)
        k = findfirst(==(s.kit), kitnames)
        kit = k === nothing ? eng.kit : get_kit(kits[k])   # load outside the audio lock
        kg = kit_gain(kit.name)
        lock(eng.lock) do
            eng.song = s
            eng.edit_pat = 1
            s.kit = kit.name
            eng.kit = kit
            eng.kitgain = kg
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
        modebtn.label[] = eng.songmode ? L("Modus: Song") : L("Modus: Pattern")
        eng.playing && play!(eng)
    end
    on(gc_menu.selection) do sel
        k = findfirst(==(sel), gc_opts)
        k === nothing && return
        m = GC_PAUSE_OPTS[k]
        m == GCPAUSE.minutes && return
        gcpause_set!(m); save_setting!("gc_pause", m)
        status[] = m == 0 ? L("GC-Pause aus.") :
                   L("GC-Pause: Speicherbereinigung beim Abspielen bis zu {1} min angehalten.", m)
    end
    on(bpm_sl.value) do v
        eng.song.bpm = v; refresh_export_info!()
        str = string(v)
        bpm_tb.stored_string[] == str || (bpm_tb.stored_string[] = str)
        bpm_tb.focused[] || bpm_tb.displayed_string[] == str || (bpm_tb.displayed_string[] = str)
    end
    on(bpm_tb.stored_string) do str             # typed tempo -> slider (which sets the song)
        valid_bpm(str) || return
        v = parse_bpm(str)
        bpm_sl.value[] == v || set_close_to!(bpm_sl, v)
    end
    on(sw_sl.value) do v
        eng.song.swing = v == 67 ? 2 / 3 : v / 100       # 67 % = exact triplet
        sw_lab.text[] = "$v%"
        refresh_export_info!()
    end
    on(sw_menu.selection) do sel
        sel === nothing && return
        eng.song.swing_on = SWING_OPTS[findfirst(==(sel), sw_opts)][2]
        refresh_export_info!()
    end
    on(raster_menu.selection) do sel
        sel === nothing && return
        old = eng.song.steps_per_beat
        new = RASTER_OPTS[findfirst(==(sel), raster_opts)][2]
        eng.song.steps_per_beat = new
        # when switching between straight and triplet grids, reset to neutral swing
        if (old in (3, 6)) != (new in (3, 6)) && eng.song.swing == default_swing(old)
            eng.song.swing = default_swing(new)
            set_close_to!(sw_sl, round(Int, 100eng.song.swing))
        end
        refresh_grid!(); refresh_export_info!()
    end
    on(kit_menu.selection) do sel
        sel === nothing && return
        k = findfirst(==(sel), kitnames)
        if k === nothing                                  # "Name (download, size)": build in background
            d = findfirst(==(sel), kit_options()) - length(kitnames)
            name = dlkits[d][1]
            post(msg) = (isready(session.kitmsg) && length(session.kitmsg.data) > 32) || put!(session.kitmsg, msg)
            name in KITS_BUILDING ? (status[] = L("Kit {1} wird schon geladen.", name)) :
                fetch_kit!(name, post, _ -> (session.kits_changed[] = true))
            cur = findfirst(==(eng.song.kit), kitnames)   # keep playing with the current kit
            cur !== nothing && (kit_menu.i_selected[] = cur)
            return
        end
        kit = get_kit(kits[k])                            # load outside the audio lock
        kg = kit_gain(kit.name)
        lock(eng.lock) do
            eng.kit = kit
            eng.kitgain = kg
        end
        eng.song.kit = sel
        show_kitgain!()
    end
    # kit gain: takes effect at once, stored per kit (in the settings) once the slider rests
    kg_sync = Ref(false)                                  # true while the slider follows a kit change
    kg_edit = Ref(0)
    function show_kitgain!()
        kg_sync[] = true
        set_close_to!(kg_sl, eng.kitgain)
        kg_sync[] = false
    end
    on(kg_sl.value) do v
        kg_sync[] && return
        eng.kitgain = Float32(v)
        n = kg_edit[] += 1
        name = eng.song.kit
        status[] = L("Gain für Kit {1}: {2} dB", name, v > 0 ? round(20log10(v), digits = 1) : "-∞")
        @async (sleep(0.6); kg_edit[] == n && set_kit_gain!(name, v))
    end
    on(fx_menu.selection) do sel
        sel === nothing && return
        eng.song.fx = sel; apply_fx!(eng)
    end
    on(v -> (eng.song.fxmix = v; apply_fx!(eng)), fx_sl.value)
    on(v -> (eng.song.master = v), mst_sl.value)

    # Tracks
    for t in 1:NTRACKS
        on(mutebtns[t].clicks) do _
            eng.song.tracks[t].mute = !eng.song.tracks[t].mute; refresh_tracks!()
        end
        on(solobtns[t].clicks) do _
            eng.song.tracks[t].solo = !eng.song.tracks[t].solo; refresh_tracks!()
        end
        on(v -> (eng.song.tracks[t].vol = v), volsls[t].value)
    end
    # Track effects
    for (f, sl) in fx_sliders
        on(sl.value) do v
            fx_updating[] && return
            tp = eng.song.tracks[fx_track[]]
            lock(eng.lock) do
                setfield!(tp, f, Float32(v))
            end
            f in (:eq_low, :eq_mid, :eq_high) && refresh_fx!()     # "track has effects" indicator
        end
    end
    on(mod_menu.selection) do sel
        (sel === nothing || fx_updating[]) && return
        k = findfirst(==(sel), mod_opts)
        k === nothing && return
        tp = eng.song.tracks[fx_track[]]
        tp.mod == k && return
        lock(eng.lock) do
            set_mod!(tp, MOD_NAMES[k])
        end
        refresh_fx!()
        k == 1 || (status[] = L("{1} auf {2} – Mix, Rate, Tiefe und Feedback einstellbar.", sel, L(TRACKS[fx_track[]][2])))
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
            status[] = L("Maximal {1} Patterns.", MAXPATTERNS)
            return
        end
        lock(eng.lock) do
            push!(eng.song.patterns, p)
        end
        eng.edit_pat = length(eng.song.patterns)
        refresh_grid!(); refresh_patbtns!()
        status[] = L("Pattern {1} angelegt. Für Song/Export in die Kette eintragen (z. B. \"1x3 {1}\").", eng.edit_pat)
    end
    on(_ -> add_pattern!(copy(cur_pattern())), addcopy.clicks)
    on(_ -> add_pattern!(Pattern(cur_pattern().steps)), addempty.clicks)
    # Fill: new pattern from the current one, last beats as a fill. Clicking again on the
    # (unchanged) fill pattern tries the next style.
    fill_src = Ref{Union{Nothing,Pattern}}(nothing)   # groove the fill was made from
    fill_pat = Ref{Union{Nothing,Pattern}}(nothing)   # last generated fill (to recognize it)
    fill_style = Ref(1)
    fill_from = Ref(1)                                # number of the source pattern (for the chain hint)
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
            length(s.patterns) >= MAXPATTERNS && (status[] = L("Maximal {1} Patterns.", MAXPATTERNS); return)
            fill_src[] = copy(cur)
            fill_style[] = 1
            add_pattern!(make_fill(cur, s.steps_per_beat, 1))
            fill_pat[] = cur_pattern()
            fill_from[] = something(findfirst(p -> p === cur, s.patterns), 1)
        end
        n = eng.edit_pat
        status[] = L("Fill „{1}“ in Pattern {2} – nochmal „+ Fill“ für den nächsten Stil. Kette z. B. \"{3}x3 {2}\".",
                     L(fill_name(fill_style[])), n, fill_from[])
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
            status[] = L("Kette ungültig – Beispiel: \"1 1 1 2\" oder \"1x3 2\".")
            return
        end
        eng.song.chain = c
        status[] = L("Kette: {1}", chain_string(c))
        refresh_export_info!()
        eng.playing && eng.songmode && play!(eng)
    end

    # File
    on(preset_menu.selection) do sel
        sel === nothing && return
        s = preset(sel)
        s.kit = eng.song.kit                  # presets keep the selected kit
        set_song!(s); set_edit!("")
        status[] = L("Preset \"{1}\" geladen ({2}).", sel, song_summary(eng.song))
        preset_menu.i_selected[] = 0          # the same preset can be selected again later
    end
    on(name_tb.stored_string) do str
        str === nothing && return
        eng.song.name = str
        cancel_overwrite!()
    end
    # take over the text of the name field even without Enter (otherwise it would be lost when
    # clicking "Speichern")
    function commit_name!()
        str = strip(something(name_tb.displayed_string[], ""))
        isempty(str) && return
        if str != eng.song.name
            eng.song.name = str
            cancel_overwrite!()
        end
        name_tb.stored_string[] == str || (name_tb.stored_string[] = str)
    end
    on(f -> f || commit_name!(), name_tb.focused)
    # Take over the typed text of a field as if Enter had been pressed (otherwise it would be lost
    # when clicking "Speichern" or exporting). Invalid input resets the display to the valid value.
    function commit_field!(tb, valid = _ -> true)
        str = tb.displayed_string[]
        (str === nothing || str == tb.stored_string[]) && return
        if valid(str)
            tb.stored_string[] = str              # triggers the normal processing
        else
            tb.displayed_string[] = tb.stored_string[]
        end
    end
    commit_chain!() = commit_field!(chain_tb)
    commit_repeats!() = commit_field!(rep_tb, str -> tryparse(Int, str) !== nothing)
    commit_bpm!() = commit_field!(bpm_tb, valid_bpm)
    commit_fields!() = (commit_name!(); commit_chain!(); commit_repeats!(); commit_bpm!())
    on(f -> f || commit_bpm!(), bpm_tb.focused)
    on(f -> f || commit_chain!(), chain_tb.focused)
    on(f -> f || commit_repeats!(), rep_tb.focused)
    # Edit mode ("Bearbeiten"): "Speichern" overwrites the file being edited without asking.
    # It is switched on when a song file is loaded or saved and off for presets, new songs and copies.
    edit_path = session.edit_path                # file being edited ("" = none), kept across rebuilds
    edit_name = session.edit_name                # song name when that file was loaded/saved
    function set_edit!(path::AbstractString)
        edit_path[] = path
        edit_name[] = path == "" ? "" : eng.song.name
        set_toggle!(edit_toggle, path != "")
        edit_lab.text[] = path == "" ? "" : basename(path)
    end
    on(edit_toggle.active) do v
        session.edit_on[] = v                     # remembered: switched off stays off after a restart
        (v && edit_path[] == "") || return
        status[] = L("Bearbeiten: Es ist noch keine Datei geladen – „Speichern“ legt sie an.")
    end
    # target file: the edited file as long as the name is unchanged, otherwise songs/<name>.toml
    save_target() = edit_toggle.active[] && edit_path[] != "" && eng.song.name == edit_name[] ?
                    edit_path[] : song_path(eng.song.name)
    on(savebtn.clicks) do _
        commit_fields!()
        path = save_target()
        own = edit_toggle.active[] && path == edit_path[]
        if isfile(path) && !own && pending_overwrite[] != path
            # first click on an existing file: only ask
            pending_overwrite[] = path
            savebtn.label[] = L("Überschreiben?")
            savebtn.buttoncolor[] = C_MUTE
            savebtn.labelcolor[] = C_TEXT
            status[] = L("\"{1}\" gibt es schon. Nochmal klicken zum Überschreiben, oder einen anderen Namen eingeben bzw. „Duplizieren“.",
                         basename(path))
            return
        end
        cancel_overwrite!()
        save_song(path, eng.song)
        set_edit!(path)
        load_menu.options[] = vcat(["—"], list_songs())
        status[] = own ? L("Überschrieben: {1}  ({2})", path, song_summary(eng.song)) :
                    L("Gespeichert: {1}  ({2})", path, song_summary(eng.song))
    end
    on(newbtn.clicks) do _
        old = eng.song
        spb = old.steps_per_beat
        s = Song(name = unique_name(L("Neuer Groove")), bpm = old.bpm, steps_per_beat = spb,
                 swing = old.swing, swing_on = old.swing_on,
                 patterns = [Pattern(spb in (2, 4) ? 16 : 4spb)], kit = old.kit,
                 repeats = old.repeats, countin = old.countin, click = old.click, mono = old.mono,
                 swap_lr = old.swap_lr)
        set_song!(s); set_edit!("")
        status[] = L("Neuer Groove \"{1}\" angelegt (BPM, Swing, Raster und Kit übernommen).", s.name)
    end
    on(dupbtn.clicks) do _
        s = copy(eng.song)
        s.name = unique_name(L("{1} Kopie", s.name))
        set_song!(s); set_edit!("")
        status[] = L("Kopie \"{1}\" angelegt – das Original bleibt unverändert.", s.name)
    end
    on(load_menu.selection) do sel
        (sel === nothing || sel == "—") && return
        path = song_file(sel)
        try
            set_song!(load_song(path)); set_edit!(path)
            status[] = L("Geladen: {1}  ({2}) – Bearbeiten an, „Speichern“ überschreibt.", path, song_summary(eng.song))
        catch e
            status[] = L("Fehler beim Laden: {1}", sprint(showerror, e))
        end
        load_menu.i_selected[] = 0            # the same song can be reloaded (from disk)
    end
    last_dir = Ref(song_dir())
    dialog_open = Ref(false)
    on(filebtn.clicks) do _
        dialog_open[] && return
        dialog_open[] = true
        status[] = L("Datei-Dialog geöffnet …")
        @async try
            path = pick_song_file(last_dir[])
            if path === nothing
                status[] = L("Kein Datei-Dialog gefunden – bitte zenity oder kdialog installieren.")
            elseif path != ""
                last_dir[] = dirname(path)
                set_song!(load_song(path)); set_edit!(path)
                status[] = L("Geladen: {1}  ({2}) – Bearbeiten an, „Speichern“ überschreibt.", path, song_summary(eng.song))
            else
                status[] = L("Laden abgebrochen.")
            end
        catch e
            status[] = L("Fehler beim Laden: {1}", sprint(showerror, e))
        finally
            dialog_open[] = false
        end
    end

    # Drum-JSON import: several files at once, each saved as a song; the first one is loaded
    function show_import!(res, src)
        isempty(res) && return
        path, song, _ = res[1]
        set_song!(load_song(path)); set_edit!(path)
        load_menu.options[] = vcat(["—"], list_songs())
        notes = unique(vcat((r[3] for r in res)...))
        names = join((r[2].name for r in res), ", ")
        status[] = L("JSON-Import ({1}): {2} – gespeichert in {3}", src, names, dirname(path)) *
                   (isempty(notes) ? "" : "  ·  " * join(notes, " · "))
    end
    on(impbtn.clicks) do _
        dialog_open[] && return
        dialog_open[] = true
        status[] = L("Datei-Dialog geöffnet …")
        @async try
            paths = pick_files(last_dir[]; title = L("Drum-JSON importieren"), exts = ("json", "txt"),
                               kind = "Drum-JSON")
            if paths === nothing
                status[] = L("Kein Datei-Dialog gefunden – bitte zenity oder kdialog installieren.")
            elseif isempty(paths)
                status[] = L("Import abgebrochen.")
            else
                last_dir[] = dirname(paths[1])
                show_import!(import_drum_json_files(paths), length(paths) == 1 ? basename(paths[1]) :
                             L("{1} Dateien", length(paths)))
            end
        catch e
            status[] = L("Import fehlgeschlagen: {1}", sprint(showerror, e))
        finally
            dialog_open[] = false
        end
    end
    function paste_import!()
        txt = clipboard_text(session.screen[])
        if !is_drum_json(txt)
            status[] = L("Zwischenablage enthält keine Drum-JSON-Komposition.")
            return
        end
        try
            song, notes = import_drum_json(txt)
            path = save_song(free_song_path(song_dir(), song), song)
            show_import!([(path, song, notes)], L("Zwischenablage"))
        catch e
            status[] = L("Import fehlgeschlagen: {1}", sprint(showerror, e))
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
    on(loop_toggle.active) do v
        eng.song.loop = v
        refresh_export_info!()
        v && (status[] = L("Loop-Export: ohne Einzähler, exakt ganze Takte, Ausklang auf den Anfang gefaltet. Am TD-27: SONG → [F2] SETUP → Loop Type = LOOP. Für ein einzelnes Pattern Kette „1“, Wiederholungen 1."))
    end
    on(swap_toggle.active) do v
        eng.song.swap_lr = v
        status[] = v ? L("Links/Rechts getauscht (Wiedergabe und Export).") : L("Links/Rechts normal.")
    end
    on(mono_toggle.active) do v
        eng.song.mono = v
        status[] = v ? L("Mono: Wiedergabe und Export einkanalig.") : L("Stereo: Wiedergabe und Export zweikanalig.")
    end
    on(expbtn.clicks) do _
        commit_fields!()
        s = eng.song
        path = joinpath(song_dir(), safe(s.name) * (s.loop ? " Loop" : "") * ".wav")
        status[] = L("Exportiere …")
        try
            t = @elapsed (path = export_wav(path, s, eng.kit))
            last_export[] = path
            warn = td27_name_warning(path)
            status[] = L("WAV geschrieben: {1}  ({2} min, {3}, {4} BPM, {5}× Kette, {6}, {7} s)", path,
                         fmt_time(song_seconds(s)), s.mono ? "mono" : "stereo", s.bpm, s.repeats,
                         s.loop ? L("nahtloser Loop") : L("Einzähler {1} Takt(e)", s.countin), round(t, digits = 1)) *
                       (warn == "" ? "" : "  ⚠ TD-27: $warn")
        catch e
            status[] = L("Export fehlgeschlagen: {1}", sprint(showerror, e))
        end
    end

    # keyboard: space = play/stop (not while typing)
    on(events(fig).keyboardbutton) do ev
        ev.action == Keyboard.press || return
        any(tb -> tb.focused[], (chain_tb, name_tb, rep_tb, bpm_tb)) && return
        if ev.key == Keyboard.space
            toggle_play()
        elseif ev.key == Keyboard.v && (Keyboard.left_control in events(fig).keyboardstate ||
                                        Keyboard.right_control in events(fig).keyboardstate)
            paste_import!()
        end
    end

    sw_lab.text[] = "$(round(Int, 100song.swing))%"
    refresh_all!()
    status[] = HELP
    if edit_path[] != ""                          # edit mode of the last session / before the rebuild
        set_toggle!(edit_toggle, session.edit_on[])
        edit_lab.text[] = basename(edit_path[])
    end
    r = session.restore[]
    if r !== nothing                              # first window after start: say what was restored
        session.restore[] = nothing
        status[] = L("Letzte Sitzung: \"{1}\"  ({2})", eng.song.name, song_summary(eng.song)) *
                   (session.edit_on[] ? L(" – Bearbeiten: {1}", basename(edit_path[])) : "")
    end

    last = Ref((-2, -2, false, 0))
    function tick!()
        while isready(session.kitmsg)
            status[] = take!(session.kitmsg)
        end
        if session.kits_changed[]
            session.kits_changed[] = false
            kits = kit_entries(); kitnames = [k.name for k in kits]; dlkits = on_demand_kits()
            kit_menu.options[] = kit_options()
            k = findfirst(==(eng.song.kit), kitnames)
            k !== nothing && (kit_menu.i_selected[] = k)
        end
        gc = gcpause_update!(eng.playing || metro_active(eng.metro))      # runs in the GUI task
        gc === :paused && (status[] = L("Speicherbereinigung angehalten für {1} min.", GCPAUSE.minutes))
        gc === :time && (status[] = L("GC-Pause abgelaufen – Speicherbereinigung läuft wieder."))
        gc === :memory && (status[] = L("Arbeitsspeicher knapp – Speicherbereinigung läuft wieder."))
        st = eng.playing ? eng.shown_step[] : -1
        pt = eng.shown_pat[]
        sp = eng.shown_seqpos[]
        cur = (st, pt, eng.playing, sp)
        cur == last[] && return
        # song mode: the grid follows the currently playing pattern
        if eng.songmode && eng.playing && 1 <= pt <= length(eng.song.patterns)
            if pt != eng.edit_pat
                eng.edit_pat = pt
                refresh_grid!()
            end
            if sp != last[][4]
                seq = eng.seq
                k = count(>(0), @view seq[1:min(sp, length(seq))])
                status[] = L("Song: Takt {1} von {2} · Pattern {3}   (Kette: {4})", k, count(>(0), seq), pt, chain_string(eng.song.chain))
            end
        end
        playhead[] = pt == eng.edit_pat ? st : -1
        for t in 1:NTRACKS; refresh_row!(t); end
        refresh_patbtns!()
        if !eng.playing && last[][3]
            playbtn.label[] = "▶  Play"
        elseif eng.playing && pt == 0
            set_if_changed!(status, L("Einzähler …"))
        end
        last[] = cur
        return
    end
    return fig, eng, tick!
end
