#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
app="$(./scripts/build.sh)"
if [ "$#" -gt 0 ]; then
  "$app/Contents/MacOS/TypingWithMyPets" "$@"
else
  open -n "$app"
fi
