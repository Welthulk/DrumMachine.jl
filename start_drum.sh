#!/usr/bin/env bash
# Starts the DrumMachine GUI from the project directory, no matter where the script is called from.
#   ./start_drum.sh            start (with build/drummachine.so, if present; asks to build it if not)
#   ./start_drum.sh --build    build sysimage for faster startup (takes a few minutes), then start
cd "$(dirname "$(readlink -f "$0")")" || exit 1

img=build/drummachine.so
key=build/manifest.key          # package versions the image was built with
julia_cmd=(julia -t auto --project=.)

# Manifest without DrumMachine's own entry: only changes to other packages make the image stale
manifest_key() {
    awk '/^\[\[deps\.DrumMachine\]\]/ {skip = 1; next} /^\[/ {skip = 0} !skip && !/^project_hash/' Manifest.toml
}

image_stale() {
    if [ -f "$key" ]; then
        ! manifest_key | cmp -s - "$key"
    else
        [ Manifest.toml -nt "$img" ]
    fi
}

build_image() {
    echo "Baue Sysimage $img (dauert einige Minuten) …"
    if "${julia_cmd[@]}" tools/build_sysimage.jl; then
        manifest_key > "$key"
        echo "Sysimage fertig."
    else
        echo "Sysimage konnte nicht gebaut werden – Start ohne Image."
        return 1
    fi
}

# ask yes/no, only in an interactive terminal; default: no
ask() {
    [ -t 0 ] || return 1
    read -r -p "$1 [j/N] " a
    case "$a" in [jJyY]*) return 0 ;; *) return 1 ;; esac
}

if [ "$1" = "--build" ]; then
    shift
    build_image
elif [ ! -f "$img" ]; then
    echo "Kein Sysimage gefunden ($img). Ohne Image dauert jeder Start deutlich länger."
    ask "Jetzt einmalig bauen (einige Minuten)?" && build_image
elif image_stale; then
    echo "Sysimage gefunden, aber veraltet: Pakete wurden seit dem Bau aktualisiert."
    if ask "Neu bauen (einige Minuten)?"; then
        build_image
    else
        echo "Start ohne Image."
        exec "${julia_cmd[@]}" run.jl "$@"
    fi
fi

if [ -f "$img" ] && ! image_stale; then
    echo "Sysimage gefunden: $img ($(date -r "$img" '+%d.%m.%Y %H:%M'))"
    exec "${julia_cmd[@]}" --sysimage="$img" run.jl "$@"
fi
echo "Start ohne Sysimage."
exec "${julia_cmd[@]}" run.jl "$@"
