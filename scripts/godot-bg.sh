#!/usr/bin/env bash
# Run Godot without taking over the desktop: windowed runs (screenshots, --shot, stage_preview,
# ui-check) go to a private Xvfb display; --headless runs pass straight through.
# Vulkan llvmpipe renders on Xvfb the same pixels as on the desktop, so goldens still match.
# Override the binary with GODOT_BIN. Opt out (show the window) with GODOT_WINDOW=1.
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
if [ -n "${GODOT_WINDOW:-}" ] || [[ " $* " == *" --headless "* ]] || ! command -v xvfb-run >/dev/null; then
  exec "$GODOT_BIN" "$@"
fi
# Parallel runs (ui-check's jobs) start their display search at different numbers: `xvfb-run -a`
# alone races when two runs pick the same free display at once.
exec env -u WAYLAND_DISPLAY xvfb-run -a -n $((100 + $$ % 800)) -s "-screen 0 1600x1200x24" "$GODOT_BIN" --display-driver x11 "$@"
