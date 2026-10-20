#!/usr/bin/env bash
# Pure-Dart safety suite on Termux without Flutter or pub dependency resolution.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pocket-core.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/lib/core" "$work/tool"
cp "$root/lib/core/"*.dart "$work/lib/core/"
cp "$root/tool/core_checks.dart" "$work/tool/"
cd "$work"
dart tool/core_checks.dart
