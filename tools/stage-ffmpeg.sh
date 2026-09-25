#!/usr/bin/env bash
# Copy the FFmpegKit frameworks into the staged YouMod.bundle and sign them.
#
# Run from the Makefile's after-stage rule. Theos relocates layout/ for rootless
# packages, so the bundle is located by search rather than by a fixed path.
#
# Signing matters: frameworks dlopen'd on a jailbroken device need a valid
# signature or the load fails with a code-signing error at runtime, not at build.
set -euo pipefail

STAGING="${1:?usage: stage-ffmpeg.sh <THEOS_STAGING_DIR>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES="$HERE/../modules/ffmpegkit"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }

if [ ! -d "$MODULES" ] || ! ls "$MODULES"/*.framework >/dev/null 2>&1; then
  printf '\033[33mwarning:\033[0m no FFmpegKit frameworks in %s — run tools/fetch-ffmpegkit.sh\n' "$MODULES" >&2
  printf '         packaging without them; the downloader will not be able to mux.\n' >&2
  exit 0
fi

BUNDLE="$(find "$STAGING" -type d -name 'YouMod.bundle' -print -quit 2>/dev/null || true)"
[ -n "$BUNDLE" ] || { printf '\033[31merror:\033[0m no YouMod.bundle under %s\n' "$STAGING" >&2; exit 1; }

info "staging FFmpegKit into ${BUNDLE#$STAGING}"
for framework in "$MODULES"/*.framework; do
  name="$(basename "$framework")"
  rm -rf "$BUNDLE/$name"
  cp -R "$framework" "$BUNDLE/$name"
  binary="$BUNDLE/$name/${name%.framework}"
  if [ -f "$binary" ] && command -v ldid >/dev/null 2>&1; then
    ldid -S "$binary" 2>/dev/null || true
  fi
done

info "staged $(ls -1d "$BUNDLE"/*.framework | wc -l | tr -d ' ') frameworks ($(du -sh "$MODULES" | cut -f1))"
