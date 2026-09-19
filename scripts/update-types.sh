#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "$repo_root/scripts/generate-types.py" ]; then
  repo_root="$PWD"
fi
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL "https://opencode.ai/config.json" -o "$tmp"
python3 "$repo_root/scripts/generate-types.py" "$tmp" "$repo_root/lib/types/generated.nix"
