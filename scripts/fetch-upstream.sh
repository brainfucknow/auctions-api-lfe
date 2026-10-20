#!/usr/bin/env bash
# Clone auctions-api-haskell at the pinned parity commit into .devcache/upstream
# (gitignored). The Haskell test suite is the spec for this port; see PARITY.md.
set -euo pipefail
PIN=6caa4853f489356360a28d76885c4bd4c52faf7c
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/.devcache/upstream"
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" fetch --quiet origin
else
  rm -rf "$DEST"
  git clone --quiet https://github.com/wallymathieu/auctions-api-haskell.git "$DEST"
fi
git -C "$DEST" checkout --quiet "$PIN"
echo "upstream pinned at $(git -C "$DEST" log -1 --format='%h %ad' --date=short)"
