#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/Resources"
swift "$ROOT/Scripts/GenerateIcon.swift" "$ROOT"
# iconutil is often unavailable or sandboxed; assemble a PNG-based .icns instead.
python3 "$ROOT/Scripts/make-icns.py"
