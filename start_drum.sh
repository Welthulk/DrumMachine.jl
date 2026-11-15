#!/usr/bin/env bash
# Starts the DrumMachine GUI from the project directory, no matter where the script is called from.
#   ./start_drum.sh            start (with build/drummachine.so, if present)
#   ./start_drum.sh --build    build sysimage for faster startup (takes a few minutes)
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
