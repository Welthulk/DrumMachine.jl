#!/usr/bin/env bash
# Startet die DrumMachine-GUI aus dem Projektverzeichnis, egal von wo das Skript aufgerufen wird.
cd "$(dirname "$(readlink -f "$0")")" || exit 1
exec julia -t auto --project=. run.jl "$@"
