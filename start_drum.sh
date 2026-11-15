#!/usr/bin/env bash
# Startet die DrumMachine-GUI aus dem Projektverzeichnis, egal von wo das Skript aufgerufen wird.
#   ./start_drum.sh            starten (mit build/drummachine.so, falls vorhanden)
#   ./start_drum.sh --build    Sysimage für schnelleren Start bauen (einige Minuten)
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [ "$1" = "--build" ]; then
    exec julia -t auto --project=. tools/build_sysimage.jl
fi

img=build/drummachine.so
if [ -f "$img" ]; then
    if [ Manifest.toml -nt "$img" ]; then
        echo "Hinweis: Pakete wurden aktualisiert – Sysimage mit ./start_drum.sh --build neu bauen."
        exec julia -t auto --project=. run.jl "$@"
    fi
    exec julia -t auto --project=. --sysimage="$img" run.jl "$@"
fi
exec julia -t auto --project=. run.jl "$@"
