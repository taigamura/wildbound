#!/usr/bin/env bash
# Screenshot UI check: renders every screen at each phone size in deterministic mode, lints the
# layout (godot/tests/ui_check.gd) and diffs against the goldens in godot/tests/golden/<w>x<h>/.
#
#   scripts/ui-check.sh                  check everything
#   scripts/ui-check.sh map battle       check some screens
#   scripts/ui-check.sh --update [...]   accept the current renders as the new goldens
#   NO_GOLDEN=1 scripts/ui-check.sh      layout rules only, no golden diff (parallel branches that will
#                                        all change the look; update the goldens once after merging)
#
# Output goes to $UI_CHECK_OUT (default /tmp/claude-1000/ui-check/<w>x<h>/): wb-<screen>.png (the shot),
# .fail.png (findings outlined: red offscreen, orange spill, magenta squashed, yellow overflow,
# cyan truncated, green art, purple contrast, white overlap) and .diff.png (pixels that changed).
# Exit code is 1 if any screen failed. Needs a real renderer (Vulkan llvmpipe works); runs on a
# private Xvfb display via scripts/godot-bg.sh, so no windows open on the desktop.
set -uo pipefail
cd "$(dirname "$0")/.."

ALL=(title team team-swap map map-sel map-warden map-late reward reward-warden upgrade party end end-win pack coll coll-trait coll-up shop battle inspect battle-shared battle-heavy)
# size and simulated safe-area insets (top,bottom): iPhone 12-16 class, and the SE (no notch)
SIZES=("390x844:47,34" "375x667:20,0")
ROOT="$PWD"
OUT="${UI_CHECK_OUT:-/tmp/claude-1000/ui-check}"
JOBS="${UI_CHECK_JOBS:-3}"

UPDATE=""
SCREENS=()
for a in "$@"; do
  case "$a" in
    --update) UPDATE="--update" ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) SCREENS+=("$a") ;;
  esac
done
[ ${#SCREENS[@]} -eq 0 ] && SCREENS=("${ALL[@]}")

run_one() {   # <screen> <size:insets>
  local screen="$1" size="${2%%:*}" safe="${2##*:}"
  local dir="$OUT/$size"
  mkdir -p "$dir"
  rm -f "$dir/wb-$screen".{png,fail.png,diff.png}
  timeout 180 "$ROOT/scripts/godot-bg.sh" --audio-driver Dummy --fixed-fps 60 --path godot --resolution "$size" -- \
    --shot="$screen" --shot-dir="$dir" --ui-check --safe="$safe" \
    ${NO_GOLDEN:+--no-golden} --golden="$ROOT/godot/tests/golden/$size" $UPDATE 2>&1 | grep -E '^(UICHECK|SCRIPT ERROR)'
  local code=${PIPESTATUS[0]}
  # 1 = findings (already printed); anything else is a crash or a timeout
  [ "$code" -le 1 ] || echo "UICHECK EXIT $screen@$size code=$code"
}
export -f run_one
export OUT UPDATE ROOT NO_GOLDEN

mkdir -p "$OUT"
LOG="$OUT/report.txt"
for s in "${SCREENS[@]}"; do for z in "${SIZES[@]}"; do echo "$s $z"; done; done |
  xargs -P "$JOBS" -L 1 bash -c 'run_one "$0" "$1"' | sort | tee "$LOG"

fails=$(grep -c '^UICHECK FAIL' "$LOG")
broken=$(grep -c -e '^UICHECK EXIT' -e '^SCRIPT ERROR' "$LOG")
passed=$(grep -c '^UICHECK PASS' "$LOG")
echo
echo "ui-check: $passed passed, $fails findings, $broken failed runs. Shots and annotated failures: $OUT"
[ "$fails" -eq 0 ] && [ "$broken" -eq 0 ]
