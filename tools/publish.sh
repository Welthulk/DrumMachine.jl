#!/usr/bin/env bash
# Builds the next public commit from a private branch: the files of <branch> without the deny list
# (tools/githooks/public-deny.sh, .publicdeny), as one commit on top of the public main. The result
# is the local branch `public`; nothing is pushed. Work tree and index are not touched.
#
#   tools/publish.sh midi "Version 1.1.0: MIDI recording and export"
#   git push <public remote> public:main
set -euo pipefail
usage='usage: tools/publish.sh <branch> "<commit message>"'
branch="${1:?$usage}"
msg="${2:?$usage}"
cd "$(git rev-parse --show-toplevel)"
die() { echo "$*" >&2; exit 1; }
[ "$(git symbolic-ref -q --short HEAD || true)" != public ] || die "Branch public is checked out, switch to another branch first."
. tools/githooks/public-deny.sh
hooks="$(git rev-parse --path-format=absolute --git-path hooks)"
for f in pre-push public-deny.sh; do
    cmp -s "tools/githooks/$f" "$hooks/$f" || die "The active hook ($hooks) differs from tools/githooks. Run tools/githooks/install.sh first."
done
pub=$(public_remote)
[ -n "$pub" ] || die "No remote points to the public repository."
git fetch -q "$pub"
base=$(git rev-parse "refs/remotes/$pub/main")
src=$(git rev-parse --verify "$branch^{commit}")
load_deny "$src"

# Tree of a commit without the denied files.
filtered_tree() {
    local idx t; idx=$(mktemp)
    GIT_INDEX_FILE=$idx git read-tree "$1"
    denied_in_tree "$1" -z | GIT_INDEX_FILE=$idx git update-index --force-remove -z --stdin
    t=$(GIT_INDEX_FILE=$idx git write-tree)
    rm -f "$idx"
    echo "$t"
}

# The public main must not have changes that are missing in <branch>: either it is an ancestor
# of <branch>, or this script built it from an ancestor of <branch> (refs/publish/<public sha>).
if ! git merge-base --is-ancestor "$base" "$src"; then
    last=$(git rev-parse -q --verify "refs/publish/$base" || true)
    if [ -z "$last" ]; then
        die "The public main ($(git log -1 --format='%h %s' "$base")) has changes that are not in $branch.
Bring them into $branch first, then publish again."
    elif ! git merge-base --is-ancestor "$last" "$src"; then
        die "The public main was built from $(git rev-parse --short "$last"), which is no longer in $branch
(history rewritten?). If $branch contains everything that is public, record that with:
  git update-ref refs/publish/$base $branch"
    fi
fi

tree=$(filtered_tree "$src")
[ -z "$(denied_in_tree "$tree")" ] || die "Denied files are still in the public tree, stopped."
[ "$tree" != "$(git rev-parse "$base^{tree}")" ] || die "Nothing to publish: $branch has no public changes."
left=$(denied_in_tree "$src")
nleft=$(( $(git ls-tree -r "$src" | wc -l) - $(git ls-tree -r "$tree" | wc -l) ))
already=$(denied_in_tree "$base")
commit=$(git commit-tree "$tree" -p "$base" -m "$msg")
git branch -f public "$commit" >/dev/null
git update-ref "refs/publish/$commit" "$src"             # source of this public commit

echo "Branch public = $(git log -1 --format='%h %s' public), on top of $pub/main ($(git rev-parse --short "$base"))."
if [ "$nleft" -gt 0 ]; then
    echo "Left out ($nleft private files):"
    n=0
    while IFS= read -r f; do
        n=$((n + 1)); [ $n -le 30 ] || { echo "  ..."; break; }
        is_denied "$f" || true
        printf '  %s   (%s)\n' "$f" "$DENIED_BY"
    done <<< "$left"
fi
if [ -n "$already" ]; then
    echo "Note: these denied files are already public; they are removed now but stay in the public history:"
    echo "$already" | sed 's/^/  /'
fi
echo "Changes: $(git diff --shortstat "$base" public)"
echo "Check:   git diff --stat $pub/main public"
echo "Publish: git push $pub public:main"
