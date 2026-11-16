# English texts (German => English) used by L(), see src/i18n.jl.
# Main window (src/gui.jl) and documentation viewer (src/docs_view.jl).
add_translations!(Dict{String,String}(
    # header, help, file dialog
    "Groove  ·  Vorhören  ·  WAV-Export" => "Groove  ·  Preview  ·  WAV export",
    "WAV-Editor" => "WAV Editor",
    "DrumMachine – Hilfe" => "DrumMachine – Help",
    "Alle Dateien" => "All files",
    "Song laden" => "Load song",
    "Sprache wird beim nächsten Öffnen übernommen." => "The language applies the next time the window opens.",
    "Bereit.  Linksklick: Schlag an/aus · Rechtsklick: Ghost → normal → Akzent · Leertaste: Play/Stop · ? = Hilfe" =>
        "Ready.  Left click: note on/off · Right click: ghost → normal → accent · Space: play/stop · ? = help",

    # transport
    "Modus: Pattern" => "Mode: Pattern",
    "Modus: Song" => "Mode: Song",
    "Einzähler" => "Count-in",
    "   GC-Pause" => "   GC pause",
    "aus" => "off",
    "GC-Pause aus." => "GC pause off.",
    "GC-Pause: Speicherbereinigung beim Abspielen bis zu {1} min angehalten." =>
        "GC pause: garbage collection halted during playback for up to {1} min.",
    "Speicherbereinigung angehalten für {1} min." => "Garbage collection halted for {1} min.",
    "GC-Pause abgelaufen – Speicherbereinigung läuft wieder." => "GC pause over – garbage collection is back on.",
    "Arbeitsspeicher knapp – Speicherbereinigung läuft wieder." => "Memory low – garbage collection is back on.",
    "Raster" => "Grid",
    "Anteil" => "Amount",
    "16tel (4 pro Schlag)" => "16ths (4 per beat)",
    "Triolen (3 pro Schlag)" => "Triplets (3 per beat)",
    "16tel-Triolen (6 pro Schlag)" => "16th triplets (6 per beat)",
    "8tel (2 pro Schlag)" => "8ths (2 per beat)",
    "32tel (8 pro Schlag)" => "32nds (8 per beat)",
    "Auto" => "Auto",
    "auf 8tel" => "on 8ths",
    "auf 16tel" => "on 16ths",

    # song summary
    "exakte Triolen" => "exact triplets",
    "Triolen-Swing {1} %" => "triplet swing {1} %",
    "kein Swing" => "no swing",
    "Swing {1} % ({2})" => "swing {1} % ({2})",
    "auf {1}tel" => "on {1}ths",
    "{1} · {2} · Kette {3}" => "{1} · {2} · chain {3}",
    "{1} BPM (Patterns mit eigenem Tempo)" => "{1} BPM (patterns with their own tempo)",
    "Pattern {1}: eigenes Tempo {2} BPM (Song: {3} BPM)." => "Pattern {1}: own tempo {2} BPM (song: {3} BPM).",
    "Pattern {1}: Song-Tempo." => "Pattern {1}: song tempo.",
    "Song" => "Song",
    "Tempo" => "Tempo",
    "Song-Tempo {1} BPM. Pattern {2} hat ein eigenes Tempo ({3} BPM, Feld „Tempo“ in der Pattern-Zeile) und bleibt dabei." =>
        "Song tempo {1} BPM. Pattern {2} has its own tempo ({3} BPM, field \"Tempo\" in the pattern row) and keeps it.",
    "Audio-Thread läuft mit Echtzeit-Priorität {1}." => "Audio thread runs with realtime priority {1}.",
    "Echtzeit-Priorität für den Audio-Thread nicht erlaubt – normale Priorität." =>
        "Realtime priority for the audio thread not allowed – normal priority.",

    # patterns and chain
    "+ Kopie" => "+ Copy",
    "+ Leer" => "+ Empty",
    "Löschen" => "Delete",
    "Leeren" => "Clear",
    "Kette" => "Chain",
    "z. B. 1x3 2" => "e.g. 1x3 2",
    "für Song-Modus und Export" => "for song mode and export",
    "Maximal {1} Patterns." => "At most {1} patterns.",
    "Pattern {1} angelegt. Für Song/Export in die Kette eintragen (z. B. \"1x3 {1}\")." =>
        "Pattern {1} created. Add it to the chain for song mode/export (e.g. \"1x3 {1}\").",
    "Fill „{1}“ in Pattern {2} – nochmal „+ Fill“ für den nächsten Stil. Kette z. B. \"{3}x3 {2}\"." =>
        "Fill “{1}” in pattern {2} – click “+ Fill” again for the next style. Chain e.g. \"{3}x3 {2}\".",
    "Kette ungültig – Beispiel: \"1 1 1 2\" oder \"1x3 2\"." => "Invalid chain – example: \"1 1 1 2\" or \"1x3 2\".",
    "Kette: {1}" => "Chain: {1}",
    "Song: Takt {1} von {2} · Pattern {3}   (Kette: {4})" => "Song: bar {1} of {2} · pattern {3}   (chain: {4})",
    "Einzähler …" => "Count-in …",

    # fill styles (FILL_STYLES names, display only)
    "Snare-Wirbel" => "Snare roll",
    "Tom-Abgang" => "Tom run",
    "Snare/Tom-Wechsel" => "Snare/tom alternation",
    "Akzente 3-3-2" => "Accents 3-3-2",
    "Snare-Crescendo" => "Snare crescendo",
    "Tom-Abgang (2 Schläge)" => "Tom run (2 beats)",
    "Ganzer Takt" => "Full bar",

    # tracks and track effects
    "HH offen" => "HH Open",
    "Ghost (o)  ·  normal (x)  ·  Akzent (X)     2 Doppelschlag  ·  z Buzz  ·  f Flam  ·  r Drag     Klick auf den Spurnamen = Vorhören + Effekte" =>
        "Ghost (o)  ·  normal (x)  ·  accent (X)     2 double stroke  ·  z buzz  ·  f flam  ·  r drag     click a track name = preview + effects",
    "{1}: links und rechts getauscht." => "{1}: left and right swapped.",
    "{1}: Stereo-Position wie im Kit." => "{1}: stereo position as in the kit.",
    "VERZIERUNGEN (Song)" => "ORNAMENTS (song)",
    "Vorschläge" => "Grace notes",
    "Verzierungen zurücksetzen" => "Reset ornaments",
    # ornaments
    "   Verzierung" => "   Ornament",
    "keine (Klick = Schlag)" => "none (click = note)",
    "Doppelschlag" => "double stroke",
    "Buzz-Roll" => "buzz roll",
    "Flam" => "flam",
    "Drag" => "drag",
    "Unbekanntes Verzierungszeichen '{1}' (erlaubt: . 2 z f r)" => "Unknown ornament character '{1}' (allowed: . 2 z f r)",
    "SPUR-EFFEKTE" => "TRACK EFFECTS",
    "Tiefen" => "Low",
    "Mitten" => "Mid",
    "Mitten bei" => "Mid freq",
    "Höhen" => "High",
    "Tiefe" => "Depth",
    "Effekt" => "Effect",
    "Aus" => "Off",
    "Effekte der Spur zurücksetzen" => "Reset track effects",
    "{1} auf {2} – Mix, Rate, Tiefe und Feedback einstellbar." => "{1} on {2} – adjust mix, rate, depth and feedback.",

    # file
    "DATEI" => "FILE",
    "Neu" => "New",
    "Duplizieren" => "Duplicate",
    "Speichern" => "Save",
    "Bearbeiten" => "Edit",
    "Überschreiben?" => "Overwrite?",
    "LADEN" => "LOAD",
    "Preset laden …" => "Load preset …",
    "Eigenen Song laden …" => "Load your song …",
    "Datei öffnen …" => "Open file …",
    "Neuer Groove" => "New Groove",
    "{1} Kopie" => "{1} copy",
    "Neuer Groove \"{1}\" angelegt (BPM, Swing, Raster und Kit übernommen)." =>
        "New groove \"{1}\" created (BPM, swing, grid and kit kept).",
    "Kopie \"{1}\" angelegt – das Original bleibt unverändert." => "Copy \"{1}\" created – the original stays unchanged.",
    "Preset \"{1}\" geladen ({2})." => "Preset \"{1}\" loaded ({2}).",
    "Bearbeiten: Es ist noch keine Datei geladen – „Speichern“ legt sie an." =>
        "Edit: no file loaded yet – “Save” creates it.",
    "\"{1}\" gibt es schon. Nochmal klicken zum Überschreiben, oder einen anderen Namen eingeben bzw. „Duplizieren“." =>
        "\"{1}\" already exists. Click again to overwrite, or enter another name or use “Duplicate”.",
    "Überschrieben: {1}  ({2})" => "Overwritten: {1}  ({2})",
    "Gespeichert: {1}  ({2})" => "Saved: {1}  ({2})",
    "Geladen: {1}  ({2}) – Bearbeiten an, „Speichern“ überschreibt." => "Loaded: {1}  ({2}) – Edit on, “Save” overwrites.",
    "Fehler beim Laden: {1}" => "Error loading: {1}",
    "Datei-Dialog geöffnet …" => "File dialog open …",
    "Kein Datei-Dialog gefunden – bitte zenity oder kdialog installieren." =>
        "No file dialog found – please install zenity or kdialog.",
    "Laden abgebrochen." => "Loading cancelled.",

    # export
    "Wiederholungen" => "Repeats",
    "Einzähler (Takte)" => "Count-in (bars)",
    "Klick" => "Click",
    "WAV exportieren" => "Export WAV",
    "Exportiere …" => "Exporting …",
    "WAV geschrieben: {1}  ({2} min, {3}, {4} BPM, {5}× Kette, {6}, {7} s)" =>
        "WAV written: {1}  ({2} min, {3}, {4} BPM, {5}× chain, {6}, {7} s)",
    "nahtloser Loop" => "seamless loop",
    "Einzähler {1} Takt(e)" => "count-in {1} bar(s)",
    "Export fehlgeschlagen: {1}" => "Export failed: {1}",
    "Loop-Export: ohne Einzähler, exakt ganze Takte, Ausklang auf den Anfang gefaltet. Am TD-27: SONG → [F2] SETUP → Loop Type = LOOP. Für ein einzelnes Pattern Kette „1“, Wiederholungen 1." =>
        "Loop export: no count-in, exact whole bars, decay folded onto the start. On the TD-27: SONG → [F2] SETUP → Loop Type = LOOP. For a single pattern use chain “1”, repeats 1.",
    "Links/Rechts getauscht (Wiedergabe und Export)." => "Left/right swapped (playback and export).",
    "Links/Rechts normal." => "Left/right normal.",
    "Mono: Wiedergabe und Export einkanalig." => "Mono: playback and export in one channel.",
    "Stereo: Wiedergabe und Export zweikanalig." => "Stereo: playback and export in two channels.",

    # WAV editor, GitHub
    "WAV-Editor ist schon offen – dort „Letzten Export öffnen“ lädt den letzten Export." =>
        "The WAV editor is already open – “Open last export” there loads the latest export.",
    "WAV-Editor geöffnet." => "WAV editor opened.",
    "Browser geöffnet: {1}" => "Browser opened: {1}",
    "Projektseite: {1}" => "Project page: {1}",

    # documentation viewer (src/docs_view.jl)
    "Keine Dokumentation gefunden in {1}" => "No documentation found in {1}",
    "Auf GitHub lesen ↗" => "Read on GitHub ↗",
    # Drum-JSON import
    "JSON-Import …" => "JSON import …",
    "Drum-JSON importieren" => "Import Drum-JSON",
    "JSON-Import ({1}): {2} – gespeichert in {3}" => "JSON import ({1}): {2} – saved in {3}",
    "Import abgebrochen." => "Import cancelled.",
    "{1} Dateien" => "{1} files",
    "Import fehlgeschlagen: {1}" => "Import failed: {1}",
    "Zwischenablage enthält keine Drum-JSON-Komposition." => "The clipboard holds no Drum-JSON composition.",
    "Zwischenablage" => "clipboard",
    "Keine Drum-JSON-Datei (Feld „tracks“ fehlt)" => "Not a Drum-JSON file (field \"tracks\" missing)",
    "Raster mit {1} Schlägen pro Viertel wird nicht unterstützt" => "A grid with {1} slots per beat is not supported",
    "Takt mit {1} Schritten ist zu lang (höchstens {2})" => "Bar with {1} steps is too long (at most {2})",
    "Unbekannter Klang „{1}“ übersprungen" => "Unknown sound \"{1}\" skipped",
    "Delays von „{1}“ nicht übernommen" => "Delays of \"{1}\" not taken over",
    "Verschiebung von „{1}“ nicht übernommen" => "Shift of \"{1}\" not taken over",
    "{1} zusammengelegt auf {2}" => "{1} merged into {2}",
    "{1} verschiedene Takte – im Programm sind nur 24 Patterns bearbeitbar" =>
        "{1} different bars – only 24 patterns can be edited in the program",
    "DrumMachine – Info" => "DrumMachine – Info",
    "Sprache wird umgestellt …" => "Switching language …",
    "Gain für Kit {1}: {2} dB" => "Gain for kit {1}: {2} dB",
    "Sitzung konnte nicht gespeichert werden" => "Session could not be saved",
    "Letzte Sitzung konnte nicht geladen werden" => "Last session could not be loaded",
    "Letzte Sitzung: \"{1}\"  ({2})" => "Last session: \"{1}\"  ({2})",
    " – Bearbeiten: {1}" => " – editing: {1}",
))
