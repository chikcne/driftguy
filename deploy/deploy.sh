#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKTREE=${DRIFTGUY_WORKTREE:-$REPO_ROOT/.claude/worktrees/production}
HOST_DIR=${DRIFTGUY_HOST_DIR:-$HOME/.t3/hosted/driftguy}
PUBLIC_URL=${DRIFTGUY_PUBLIC_URL:-}
KEEP=5

if [[ ! -d "$WORKTREE" ]]; then
  git -C "$REPO_ROOT" worktree add "$WORKTREE" production
fi

cd "$WORKTREE"
if [[ "$(git branch --show-current)" != production ]]; then
  echo "worktree is not on the production branch" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "production worktree has uncommitted changes; refusing to deploy" >&2
  exit 1
fi

sha=$(git rev-parse --short HEAD)
release="$HOST_DIR/releases/$sha"
mkdir -p "$HOST_DIR/releases"

pnpm install --frozen-lockfile
pnpm exec tsc --noEmit
rm -rf "$release.tmp"
pnpm exec vite build --outDir "$release.tmp" --emptyOutDir
rm -rf "$release"
mv "$release.tmp" "$release"
git log -1 --format='%h %s (%ci)' > "$release/VERSION.txt"

ln -sfn "releases/$sha" "$HOST_DIR/current.tmp"
mv -T "$HOST_DIR/current.tmp" "$HOST_DIR/current"

cd "$HOST_DIR/releases"
ls -1t | tail -n +$((KEEP + 1)) | { grep -vx "$sha" || true; } | xargs -r rm -rf

echo "deployed $sha${PUBLIC_URL:+ -> $PUBLIC_URL}"
