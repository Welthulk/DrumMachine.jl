# English texts (German => English) used by L(), see src/i18n.jl.
# MIDI recording from an e-drum kit (src/midi.jl, transport row in src/gui.jl).
add_translations!(Dict{String,String}(
    "● Aufnahme" => "● Record",
    "Mithören" => "Monitor",
    "E-Drum per USB: „Aufnahme“ trägt die Schläge ins laufende Pattern ein (Docs → MIDI)" =>
        "E-drum by USB: “Record” writes the hits into the playing pattern (Docs → MIDI)",
    "Aufnahme an, aber kein MIDI-Eingang gewählt (Menü MIDI)." =>
        "Recording on, but no MIDI input chosen (menu MIDI).",
    "Aufnahme beendet: {1} Schläge eingetragen." => "Recording stopped: {1} hits written.",
    "Aufnahme läuft: Schläge kommen ins laufende Pattern, Stop beendet die Aufnahme." =>
        "Recording: hits go into the playing pattern, Stop ends the recording.",
    "Kein MIDI-Eingang gefunden (TD-27: USB-Treiber auf GENERIC stellen, siehe Docs → MIDI)." =>
        "No MIDI input found (TD-27: set the USB driver to GENERIC, see Docs → MIDI).",
    "MIDI: {1} · Note {2} · Velocity {3}" => "MIDI: {1} · note {2} · velocity {3}",
    "  →  Pattern {1}, Step {2} ({3} ms)" => "  →  pattern {1}, step {2} ({3} ms)",
    "MIDI-Eingang: {1}" => "MIDI input: {1}",
    "MIDI-Eingang: {1}. Jeder Schlag erscheint hier, „Aufnahme“ trägt ihn ins Pattern ein." =>
        "MIDI input: {1}. Every hit shows up here, “Record” writes it into the pattern.",
    "MIDI-Eingang „{1}“ lässt sich nicht öffnen." => "MIDI input \"{1}\" cannot be opened.",
    "MIDI-Eingang aus." => "MIDI input off.",
    "MIDI-Eingänge: {1}" => "MIDI inputs: {1}",
    "MIDI-Gerät „{1}“ nicht gefunden, im MIDI-Menü wählen oder ↻ drücken." =>
        "MIDI device \"{1}\" not found, choose one in the MIDI menu or press ↻.",
    "MIDI: Note {1} (Velocity {2}) ist keiner Spur zugeordnet, siehe [midi_map] in Docs → MIDI." =>
        "MIDI: note {1} (velocity {2}) is not mapped to a track, see [midi_map] in Docs → MIDI.",
    "Mithören an: jeder Schlag spielt auch den Kit-Klang, verzögert um den Audio-Puffer." =>
        "Monitor on: every hit also plays the kit sound, delayed by the audio buffer.",
    "Mithören aus." => "Monitor off.",
    "„{1}“ ist keine gültige MIDI-Datei: {2}" => "\"{1}\" is not a valid MIDI file: {2}",
    "Datei abgeschnitten" => "file is cut off",
    "Längenangabe zu lang" => "length value too long",
    "kein MIDI-Kopf (MThd)" => "no MIDI header (MThd)",
    "Format {1} wird nicht unterstützt, nur 0 und 1" => "format {1} is not supported, only 0 and 1",
    "Zeitbasis 0" => "time base 0",
    "ungültige SMPTE-Zeitbasis" => "invalid SMPTE time base",
    "Datenbyte ohne Status" => "data byte without status",
    "unbekanntes Ereignis 0x{1}" => "unknown event 0x{1}",
    "keine Spur (MTrk)" => "no track (MTrk)",
    "MIDI-Datei länger als 60 min: {1}" => "MIDI file longer than 60 min: {1}",
))
