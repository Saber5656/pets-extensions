#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
app="$(./scripts/build.sh)"
export TWMP_CODEX_WORKDIR="$PWD"
if [ "$#" -gt 0 ]; then
  "$app/Contents/MacOS/TypingWithMyPets" "$@"
else
  launchctl setenv TWMP_CODEX_WORKDIR "$TWMP_CODEX_WORKDIR" 2>/dev/null || true
  open -n "$app"
fi
