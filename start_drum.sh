#!/usr/bin/env bash
# Starts the DrumMachine GUI from the project directory, no matter where the script is called from.
#   ./start_drum.sh            start (with build/drummachine.so, if present; asks to build it if not)
#   ./start_drum.sh --build    build sysimage for faster startup (takes a few minutes), then start
#   ./start_drum.sh --no-image start without sysimage (no questions; e.g. to rule out a stale image)
#   ./start_drum.sh --player   only the setup player (for the stage)
#   ./start_drum.sh --prio     high priority: nice up to -15, realtime audio thread (if allowed)
#   ./start_drum.sh --help     list the options; options can be combined
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

usage() {
    cat <<'HELP'
Aufruf: ./start_drum.sh [Optionen]

  (ohne)        Start mit Sysimage build/drummachine.so, falls vorhanden und aktuell;
                fehlt es oder ist es veraltet, wird gefragt, ob es gebaut werden soll
  --build       Sysimage neu bauen (einige Minuten), danach starten
  --no-image    ohne Sysimage starten, keine Rückfragen (langsamerer Start)
  --player      nur den Setup-Player starten (für die Bühne)
  --prio        hohe Priorität: Programm mit nice bis -15, Audio-Thread in Echtzeit
                (braucht einmalig: sudo groupadd -f pipewire && sudo usermod -aG pipewire $USER,
                dann neu anmelden)
  -h, --help    diese Hilfe

Optionen lassen sich kombinieren, z. B. ./start_drum.sh --prio --player
HELP
}

build=0; noimage=0; prio=0; args=()
for a in "$@"; do
    case "$a" in
        -h|--help) usage; exit 0 ;;
        --build) build=1 ;;
        --no-image) noimage=1 ;;
        --prio) prio=1 ;;
        *) args+=("$a") ;;                       # e.g. --player, passed on to run.jl
    esac
done

# --prio: use what the system allows (RLIMIT_NICE, RLIMIT_RTPRIO); never needs root at start
launch=()
if [ "$prio" = 1 ]; then
    e=$(ulimit -e); r=$(ulimit -r)
    ok=0
    if [ "$e" = unlimited ] || [ "$e" -gt 20 ]; then
        n=$([ "$e" = unlimited ] && echo 15 || echo $(( e - 20 )))
        [ "$n" -gt 15 ] && n=15
        launch=(nice -n "-$n"); ok=1
        echo "Hohe Priorität: nice -$n"
    fi
    if [ "$r" = unlimited ] || [ "$r" -gt 0 ]; then
        rp=$([ "$r" = unlimited ] && echo 70 || echo "$r")
        [ "$rp" -gt 70 ] && rp=70
        export DRUMMACHINE_RT="$rp"; ok=1
        echo "Echtzeit-Priorität für den Audio-Thread: $rp"
    fi
    if [ "$ok" = 0 ]; then
        echo "Hohe Priorität nicht möglich: dem Benutzer fehlen die Rechte (nice/rtprio = 0)."
        if getent group pipewire > /dev/null || grep -qs '^@pipewire.*rtprio' /etc/security/limits.d/*; then
            echo "Einmalig einrichten:  sudo groupadd -f pipewire && sudo usermod -aG pipewire $USER"
            echo "und danach ab- und wieder anmelden."
        else
            echo "Einmalig einrichten: Gruppe mit rtprio/nice in /etc/security/limits.d anlegen (z. B. audio)."
        fi
        echo "Start mit normaler Priorität."
    fi
fi

run() {
    exec "${launch[@]}" "${julia_cmd[@]}" "$@" run.jl "${args[@]}"
}

if [ "$noimage" = 1 ]; then
    echo "Start ohne Sysimage (--no-image)."
    run
fi

if [ "$build" = 1 ]; then
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
        run
    fi
fi

if [ -f "$img" ] && ! image_stale; then
    echo "Sysimage gefunden: $img ($(date -r "$img" '+%d.%m.%Y %H:%M'))"
    run --sysimage="$img"
fi
echo "Start ohne Sysimage."
run
