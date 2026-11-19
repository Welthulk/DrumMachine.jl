#!/usr/bin/env bash
# Installs the pre-push hook that keeps private files out of the public repo. The hook is copied
# into .git/hooks and core.hooksPath points there (overriding a global setting), so it stays
# active on branches without tools/githooks and in all worktrees.
# Run again after changing tools/githooks; tools/publish.sh refuses to run with an outdated copy.
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)"
hooks="$(git rev-parse --path-format=absolute --git-common-dir)/hooks"
mkdir -p "$hooks"
cp "$src/pre-push" "$src/public-deny.sh" "$hooks/"
chmod +x "$hooks/pre-push"
git config core.hooksPath "$hooks"
active="$(git rev-parse --path-format=absolute --git-path hooks)"
if [ "$active" != "$hooks" ]; then
    echo "Git uses the hooks in $active (core.hooksPath set elsewhere: $(git config --show-origin --get-all core.hooksPath | tr '\n' ' ')), the hook would not run." >&2
    exit 1
fi
echo "pre-push hook installed in $hooks"
