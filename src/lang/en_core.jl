# English texts (German => English) used by L(), see src/i18n.jl.
# Messages of the core files (errors and warnings that can reach the status line or terminal).
add_translations!(Dict{String,String}(
    # song.jl
    "Unbekannter Effekt {1} (erlaubt: {2})" => "Unknown effect {1} (allowed: {2})",
    "swing_on muss 0 (Auto), 8 oder 16 sein" => "swing_on must be 0 (auto), 8 or 16",
    "Unbekanntes Rasterzeichen '{1}' (erlaubt: . o x X)" => "Unknown grid character '{1}' (allowed: . o x X)",
    "Unbekannte Spur {1} ignoriert" => "Unknown track {1} ignored",
    "Unbekannter Effekt {1} ignoriert" => "Unknown effect {1} ignored",
    # kit.jl
    "Unbekanntes Instrument {1}" => "Unknown instrument {1}",
    "Kit {1}: keine Samples für {2} gefunden, nutze Synth-Klang" => "Kit {1}: no samples found for {2}, using synth sound",
    "Kit {1} konnte nicht geladen werden" => "Kit {1} could not be loaded",
    # engine.jl
    "Julia läuft mit nur einem Thread – Audio kann stottern. Starte mit `julia -t auto`." =>
        "Julia is running with a single thread – audio may stutter. Start with `julia -t auto`.",
    "bits muss 16 oder 24 sein" => "bits must be 16 or 24",
    "Name hat {1} Zeichen, das TD-27 zeigt nur 16" => "name has {1} characters, the TD-27 shows only 16",
    "Name endet auf _Click – das TD-27 hält die Datei für eine Klick-Spur" =>
        "name ends in _Click – the TD-27 takes the file for a click track",
    # presets.jl
    "Preset-Zeilen unterschiedlich lang: {1}" => "Preset rows differ in length: {1}",
    "Unbekanntes Preset \"{1}\". Verfügbar: {2}" => "Unknown preset \"{1}\". Available: {2}",
    # wavedit.jl
    "Keine Auswahl" => "No selection",
    "Auswahl ist leer" => "Selection is empty",
    "Abtastrate {1} wird nicht unterstützt" => "Sample rate {1} is not supported",
    "Bittiefe {1} wird nicht unterstützt (16, 24 oder 32)" => "Bit depth {1} is not supported (16, 24 or 32)",
    "BPM muss größer als 0 sein" => "BPM must be greater than 0",
    "Unbekannter Effekt {1}" => "Unknown effect {1}",
    "Effekte gehen nur bei Mono und Stereo" => "Effects work only on mono and stereo",
    # kitbuild.jl
    "{1}: Instrument {2}/{3} ({4})" => "{1}: instrument {2}/{3} ({4})",
    "{1} fertig: {2}" => "{1} ready: {2}",
    "{1} wird geladen: {2} % ({3} von {4} MB)" => "Downloading {1}: {2} % ({3} of {4} MB)",
    "Zum Entpacken wird bsdtar (Paket libarchive-tools) oder {1} benötigt." =>
        "Extracting needs bsdtar (package libarchive-tools) or {1}.",
    "{1} wird entpackt …" => "Extracting {1} …",
    "Kein Samples/oh unter {1} gefunden" => "No Samples/oh found below {1}",
    "Keine Aufnahme für {1}" => "No recording for {1}",
    "Keine Dateien für {1}/{2}" => "No files for {1}/{2}",
    "Erster Start: Kit {1} wird geladen ({2}, läuft im Hintergrund) …" =>
        "First start: downloading kit {1} ({2}, runs in the background) …",
    "Kit {1} konnte nicht geladen werden: {2}" => "Kit {1} could not be loaded: {2}",
))
