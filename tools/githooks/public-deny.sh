# Deny list for the public repository, sourced by the pre-push hook and tools/publish.sh.
#
# Files matching the list never go into the public repo (github.com/Welthulk/DrumMachine.jl).
# The built-in rules below always apply and cannot be lifted. `.publicdeny` adds the names of
# private songs; it is committed only to the private repo. The hook reads it from every work tree
# and from every local and remote-tracking branch; a file denied by any of these copies stays out.
#
# Patterns in .publicdeny: matched against the whole path, case-insensitive; `*` (also matches `/`)
# and `?` are wildcards, everything else is literal (brackets and parentheses too). A leading `/`
# is ignored; a name without wildcards also covers everything below it (a folder). `!pattern`
# makes an exception within the same file; the last matching line wins.
#
# Needs bash 4 or newer.

shopt -s extglob
export LC_ALL=C.UTF-8                  # case folding of umlauts, independent of the user's locale
export GIT_NO_REPLACE_OBJECTS=1        # check the objects that are really pushed

PUBLIC_URL_RE='(^|[:/])welthulk/+drummachine\.jl(\.git)?/*$'
PRIVATE_URL_RE='(^|[:/])welthulk/+drummachine-privat\.jl(\.git)?/*$'
PUBLIC_DENY_SEP=$'\x01'

PUBLIC_DENY_BUILTIN=(
    '.publicdeny' '*/.publicdeny'
    'privat/*' '*/privat/*'
    'CLAUDE.md' '*/CLAUDE.md' 'CLAUDE.local.md' '*/CLAUDE.local.md' '.claude/*' '*/.claude/*'
    '*.wav' '*.wav.tmp' '*.m4a' '*.mp3' '*.flac' '*.ogg' '*.aac' '*.json' '*.mid' '*.midi'
    '!kits/BlackPearl/[0-9][0-9]-+([A-Za-z])-[0-9][0-9]-+([A-Za-z])-[0-9].wav'
    '!test/drum_json_example.json'
)

_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Is URL $1 the public repository? Any host spelling (ssh alias, port, https) counts.
is_public_url() { [[ $(_lower "$1") =~ $PUBLIC_URL_RE ]]; }
# Is URL $1 the private repository? Pushes there are not checked; all others are.
is_private_url() { [[ $(_lower "$1") =~ $PRIVATE_URL_RE ]]; }

# Name of the remote that points to the public repository (empty if none).
public_remote() {
    local r u
    for r in $(git remote); do
        for u in $(git config --get-all "remote.$r.url") $(git config --get-all "remote.$r.pushurl"); do
            if is_public_url "$u"; then echo "$r"; return 0; fi
        done
    done
    return 0
}

# Name in Unicode NFC (umlauts as one character). Fails if it cannot be normalized.
nfc() {
    if [[ $1 != *[![:ascii:]]* ]]; then printf '%s' "$1"; return 0; fi
    if command -v uconv >/dev/null && printf '%s' "$1" | uconv -f utf-8 -t utf-8 -x any-nfc --callback stop 2>/dev/null; then
        return 0
    fi
    if command -v python3 >/dev/null; then
        python3 -c 'import sys,unicodedata
b = sys.argv[1].encode("utf-8", "surrogateescape").decode("utf-8")
sys.stdout.buffer.write(unicodedata.normalize("NFC", b).encode("utf-8"))' "$1" 2>/dev/null && return 0
    fi
    return 1
}

# Appends the patterns of one .publicdeny text ($1, found in $2) to UDENY, as a block of its own.
_add_deny_text() {
    local l
    UDENY+=("$PUBLIC_DENY_SEP$2")
    while IFS= read -r l || [ -n "$l" ]; do
        l="${l#$'\xef\xbb\xbf'}"; l="${l%$'\r'}"
        l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"     # trim
        [[ -z $l || $l == \#* ]] && continue
        l="${l#./}"; l="${l#/}"
        [[ $l == */ ]] && l="$l*"
        l=$(nfc "$l") || continue
        UDENY+=("$l")
        DENY_PATTERNS=$((DENY_PATTERNS + 1))
        [[ $l == '!'* || $l == *[*?]* ]] || UDENY+=("$l/*")             # folder name
    done <<< "$1"
}

# Loads the built-in rules into DENY and every copy of .publicdeny into UDENY: all work trees,
# all local and remote-tracking branches, and the commits given as arguments. Fails if there is
# no copy with at least one pattern, or a copy in a work tree cannot be read.
load_deny() {
    local f w k seen=" " ref name id txt
    DENY=("${PUBLIC_DENY_BUILTIN[@]}")
    UDENY=(); DENY_PATTERNS=0
    while read -r k w; do
        [ "$k" = worktree ] || continue
        f="$w/.publicdeny"
        [ -e "$f" ] || continue
        txt=$(cat "$f") || { echo "Cannot read $f, stopped." >&2; return 1; }
        _add_deny_text "$txt" "$f"
    done < <(git worktree list --porcelain)
    while read -r name ref; do
        id=$(git rev-parse -q --verify "$ref:.publicdeny" 2>/dev/null) || continue
        [[ $seen == *" $id "* ]] && continue
        seen+="$id "
        _add_deny_text "$(git cat-file blob "$id")" ".publicdeny on $name"
    done < <(for a in "$@"; do echo "$a $a"; done
             git for-each-ref --format='%(refname:short) %(objectname)' refs/heads refs/remotes)
    if [ "$DENY_PATTERNS" -eq 0 ]; then
        echo "No .publicdeny with patterns found (work trees or branches), stopped." >&2
        return 1
    fi
    return 0
}

# Does path $1 match pattern $2? Literal match, or glob with only * and ? as wildcards.
_match() {
    local f="$1" p="$2" g
    [[ $f == "$p" ]] && return 0
    g="${p//\\/\\\\}"; g="${g//\[/\\[}"; g="${g//\]/\\]}"; g="${g//\(/\\(}"; g="${g//\)/\\)}"
    [[ $f == $g ]]
}

# Exit status 0 if path $1 is denied; DENIED_BY then says which rule set denied it. Names that
# cannot be normalized are denied.
is_denied() {
    local f="$1" p r=1 cm=0 out=1 src=""
    DENIED_BY=""
    if [[ $f == *[![:ascii:]]* ]]; then f=$(nfc "$f") || { DENIED_BY="name not valid UTF-8"; return 0; }; fi
    shopt -q nocasematch && cm=1
    shopt -s nocasematch
    for p in "${DENY[@]}"; do                       # built-in rules (real globs)
        if [[ $p == '!'* ]]; then [[ $f == ${p:1} ]] && r=1; else [[ $f == $p ]] && r=0; fi
    done
    if [ $r = 0 ]; then
        out=0; DENIED_BY="built-in rule"
    else
        r=1
        for p in "${UDENY[@]}" "$PUBLIC_DENY_SEP"; do   # each .publicdeny on its own
            if [[ $p == "$PUBLIC_DENY_SEP"* ]]; then
                [ $r = 0 ] && { out=0; DENIED_BY="$src"; break; }
                r=1; src="${p:1}"
            elif [[ $p == '!'* ]]; then
                _match "$f" "${p:1}" && r=1
            else
                _match "$f" "$p" && r=0
            fi
        done
    fi
    [ $cm = 1 ] || shopt -u nocasematch
    return $out
}

# Prints the denied files of a commit or tree $1, one per line (NUL-terminated with -z as $2).
denied_in_tree() {
    local f e='\n'
    [ "${2:-}" = -z ] && e='\0'
    git ls-tree -r --name-only -z "$1" | while IFS= read -r -d '' f; do
        is_denied "$f" && printf "%s$e" "$f"
    done
    return 0
}
