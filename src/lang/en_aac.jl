# English texts (German => English) used by L(), see src/i18n.jl.
add_translations!(Dict{String,String}(
    "ffmpeg ist nicht installiert – für AAC bitte ffmpeg installieren (z. B. sudo apt install ffmpeg)." =>
        "ffmpeg is not installed – AAC needs ffmpeg (e.g. sudo apt install ffmpeg).",
    "ffmpeg-Fehler: {1}" => "ffmpeg error: {1}",
    "AAC braucht das Programm ffmpeg (z. B. sudo apt install ffmpeg)." => "AAC needs the program ffmpeg (e.g. sudo apt install ffmpeg).",
    "Format AAC: „Speichern“ schreibt eine .m4a neben die WAV (z. B. für WhatsApp). Die WAV bleibt unverändert." =>
        "Format AAC: \"Save\" writes an .m4a next to the WAV (e.g. for WhatsApp). The WAV stays unchanged.",
    "AAC gespeichert: {1} – die WAV ist unverändert." => "AAC saved: {1} – the WAV is unchanged.",
    "AAC speichern" => "Save AAC",
    "AAC-Dateien" => "AAC files",
))
