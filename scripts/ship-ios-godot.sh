#!/usr/bin/env bash
# Build the Godot port (godot/) into a signed App Store ipa on the Mac build server
# and submit it to TestFlight with eas submit. Run from this (Linux) box, repo root.
#
#   scripts/ship-ios-godot.sh [--no-submit] [--unsigned] [--sync-local] [--build-number N]
#
#   --no-submit      build and copy the ipa back, but do not upload it
#   --unsigned       no credentials needed: export the Xcode project and run an unsigned
#                    xcodebuild build (proves Godot + templates + Xcode); implies --no-submit
#   --sync-local     build the local working tree of godot/ (rsynced to the Mac) instead
#                    of origin/main as pulled on the Mac. For testing only: never submit this
#   --build-number N override CFBundleVersion (default: godot/ios/build-number.txt + 1)
#
# Version: CFBundleShortVersionString is application/short_version in
# godot/export_presets.cfg. Build number: godot/ios/build-number.txt holds the LAST
# number uploaded to App Store Connect; this script uses +1 and, only after a
# successful submit, writes the new number back. The caller commits that file.
#
# Credentials (never committed): app/credentials.json + app/credentials/ios/*, as
# written by `cd app && npx eas-cli@24.10.0 credentials -p ios` (production → download).
# They are copied to a private temp dir on the Mac each run and deleted afterwards;
# the certificate goes into a throwaway keychain (see godot/ios/mac-build.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_KEY="$HOME/.ssh/simple-bookkeeping-buildserver"
MAC="taigamura@192.168.50.175"
MAC_REPO="dev/wildbound"            # relative to the Mac's home
MAC_LOG_NAME="wildbound-godot-build.log"
EAS_CLI="eas-cli@24.10.0"
POLL_SECS=30
TIMEOUT_MINS=75

SUBMIT=1; UNSIGNED=0; SYNC_LOCAL=0; BUILD_NUMBER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-submit) SUBMIT=0; shift ;;
    --unsigned) UNSIGNED=1; SUBMIT=0; shift ;;
    --sync-local) SYNC_LOCAL=1; shift ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30)
rsh() { ssh "${SSH_OPTS[@]}" "$MAC" "export PATH=/usr/local/bin:/opt/homebrew/bin:\$PATH; $*"; }

[ "$SYNC_LOCAL" = 1 ] && [ "$SUBMIT" = 1 ] && die "--sync-local builds uncommitted files; use it with --no-submit"

# --- version + build number -------------------------------------------------------
PRESET="$ROOT/godot/export_presets.cfg"
COUNTER="$ROOT/godot/ios/build-number.txt"
VERSION="$(sed -nE 's/^application\/short_version="([^"]+)"/\1/p' "$PRESET" | head -1)"
[ -n "$VERSION" ] || die "no application/short_version in $PRESET"
LAST="$(tr -dc '0-9' < "$COUNTER")"
[ -n "$LAST" ] || die "$COUNTER is empty"
[ -n "$BUILD_NUMBER" ] || BUILD_NUMBER=$((LAST + 1))
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "--build-number must be an integer"
[ "$BUILD_NUMBER" -gt "$LAST" ] || [ "$SUBMIT" = 0 ] || die "build $BUILD_NUMBER is not above the last upload ($LAST); App Store Connect would reject it"
say "Wildbound $VERSION ($BUILD_NUMBER) — $([ $UNSIGNED = 1 ] && echo 'unsigned test build' || echo signed)$([ $SUBMIT = 1 ] && echo ', will submit' || echo ', no submit')"

# --- credentials (local) -----------------------------------------------------------
if [ "$UNSIGNED" = 0 ]; then
  CJ="$ROOT/app/credentials.json"
  [ -f "$CJ" ] || die "missing $CJ. Download the signing credentials first:
  cd app && npx $EAS_CLI credentials -p ios
  (choose: production → credentials.json: Upload/Download → Download credentials from EAS to credentials.json)"
  CREDS="$(python3 - "$CJ" "$ROOT/app" <<'PY'
import json, os, sys
c = json.load(open(sys.argv[1]))["ios"]
if "distributionCertificate" not in c:   # multi-target form: {"Target": {...}}
    c = next(iter(c.values()))
base = sys.argv[2]
print(os.path.join(base, c["distributionCertificate"]["path"]))
print(os.path.join(base, c["provisioningProfilePath"]))
print(c["distributionCertificate"]["password"])
PY
  )" || die "cannot parse $CJ"
  P12="$(sed -n 1p <<< "$CREDS")"; PROFILE="$(sed -n 2p <<< "$CREDS")"; P12PW="$(sed -n '3,$p' <<< "$CREDS")"
  [ -f "$P12" ] || die "certificate not found: $P12"
  [ -f "$PROFILE" ] || die "provisioning profile not found: $PROFILE"
fi

# --- Mac: source -------------------------------------------------------------------
say "Checking the build server"
rsh 'godot --version && xcodebuild -version | head -1' || die "cannot reach the Mac (or godot missing there)"

WORK="$(rsh 'mktemp -d /tmp/wildbound-ios.XXXXXX')"
[ -n "$WORK" ] || die "mktemp failed on the Mac"
STARTED=0
cleanup_local() {
  rc=$?
  if [ "$STARTED" = 0 ]; then
    # The Mac script never ran, so nothing else will delete the copied credentials.
    rsh "rm -rf '$WORK'" >/dev/null 2>&1 || true
  fi
  [ $rc -eq 0 ] || echo "(Mac log: ~/$MAC_LOG_NAME, work dir $WORK)" >&2
}
trap cleanup_local EXIT

if [ "$SYNC_LOCAL" = 1 ]; then
  say "Syncing the local godot/ working tree to the Mac (test build)"
  rsync -a --delete --exclude .godot/ --exclude build/ -e "ssh ${SSH_OPTS[*]}" \
    "$ROOT/godot/" "$MAC:$WORK/src/"
  SRC="$WORK/src"
else
  say "Fast-forwarding ~/$MAC_REPO on the Mac to origin/main"
  rsh "cd ~/$MAC_REPO && git checkout -q main && git pull --ff-only -q origin main && git log --oneline -1" \
    || die "git pull --ff-only failed on the Mac; inspect ~/$MAC_REPO there (never reset --hard)"
  MAC_HEAD="$(rsh "git -C ~/$MAC_REPO rev-parse HEAD")"
  LOCAL_HEAD="$(git -C "$ROOT" rev-parse HEAD)"
  if [ "$MAC_HEAD" != "$LOCAL_HEAD" ]; then
    echo "WARNING: the Mac builds ${MAC_HEAD:0:7} (origin/main) but local HEAD is ${LOCAL_HEAD:0:7}. Push/merge first if that's not intended." >&2
  fi
  if ! git -C "$ROOT" diff --quiet HEAD -- godot/ || [ -n "$(git -C "$ROOT" ls-files --others --exclude-standard godot/)" ]; then
    echo "WARNING: godot/ has uncommitted changes locally; they are NOT in this build." >&2
  fi
  SRC="\$HOME/$MAC_REPO/godot"
fi

# Always run the Mac half from this checkout so both halves match.
scp "${SSH_OPTS[@]}" -q "$ROOT/godot/ios/mac-build.sh" "$MAC:$WORK/mac-build.sh"

if [ "$UNSIGNED" = 0 ]; then
  say "Copying signing credentials to $WORK on the Mac"
  rsh "chmod 700 '$WORK'"
  scp "${SSH_OPTS[@]}" -q "$P12" "$MAC:$WORK/dist.p12"
  scp "${SSH_OPTS[@]}" -q "$PROFILE" "$MAC:$WORK/profile.mobileprovision"
  printf '%s' "$P12PW" | rsh "umask 077; cat > '$WORK/dist.p12.password'"
fi

# --- Mac: build (detached) -----------------------------------------------------------
say "Starting the build on the Mac (log: ~/$MAC_LOG_NAME)"
ARGS="--work '$WORK' --src \"$SRC\" --build-number $BUILD_NUMBER --version $VERSION"
[ "$UNSIGNED" = 1 ] && ARGS="$ARGS --unsigned"
PID="$(rsh "nohup bash '$WORK/mac-build.sh' $ARGS > ~/$MAC_LOG_NAME 2>&1 < /dev/null & echo \$!")"
[ -n "$PID" ] || die "could not start the Mac build"
STARTED=1
echo "pid $PID"

DEADLINE=$(( $(date +%s) + TIMEOUT_MINS * 60 ))
LAST_LINE=""
while :; do
  sleep "$POLL_SECS"
  # A dropped SSH connection is not fatal: the build runs under nohup. Just retry.
  STATE="$(rsh "if kill -0 $PID 2>/dev/null; then echo running; else echo done; fi; tail -1 ~/$MAC_LOG_NAME" 2>/dev/null)" || { echo "(ssh poll failed, retrying)"; continue; }
  RUN="$(echo "$STATE" | head -1)"; LINE="$(echo "$STATE" | sed -n 2p)"
  if [ "$LINE" != "$LAST_LINE" ]; then echo "  ${LINE:0:160}"; LAST_LINE="$LINE"; fi
  [ "$RUN" = done ] && break
  [ "$(date +%s)" -lt "$DEADLINE" ] || die "build still running after $TIMEOUT_MINS min (pid $PID on the Mac). Check ~/$MAC_LOG_NAME"
done

STATUS="$(rsh "cat '$WORK/status' 2>/dev/null")" || true
if [[ "$STATUS" != ok* ]]; then
  echo "---- last 60 lines of ~/$MAC_LOG_NAME ----" >&2
  rsh "tail -60 ~/$MAC_LOG_NAME" >&2 || true
  rsh "rm -rf '$WORK'" >/dev/null 2>&1 || true
  die "Mac build failed: ${STATUS:-no status written}"
fi
RESULT="${STATUS#ok }"
rsh "grep -E '^\[[0-9]{2}:|ARCHIVE SUCCEEDED|EXPORT SUCCEEDED|ipa Info|Authority=|TeamIdentifier=' ~/$MAC_LOG_NAME | tail -12" || true

if [ "$UNSIGNED" = 1 ]; then
  say "Unsigned build OK: $RESULT (on the Mac)"
  rsh "rm -rf '$WORK'" || true
  exit 0
fi

# --- copy back -------------------------------------------------------------------------
mkdir -p "$ROOT/dist/ios"
LOCAL_IPA="$ROOT/dist/ios/$(basename "$RESULT")"
scp "${SSH_OPTS[@]}" -q "$MAC:$RESULT" "$LOCAL_IPA" || die "scp of the ipa failed"
rsh "rm -rf '$WORK'" || true
SIZE=$(stat -c %s "$LOCAL_IPA")
[ "$SIZE" -gt 1000000 ] || die "copied ipa is only $SIZE bytes"
say "ipa: $LOCAL_IPA ($((SIZE / 1024 / 1024)) MB)"

if [ "$SUBMIT" = 0 ]; then
  say "Done (--no-submit). Build number file left at $LAST."
  exit 0
fi

# --- submit ------------------------------------------------------------------------------
say "Submitting to App Store Connect via EAS"
SUBMIT_LOG="$ROOT/dist/ios/submit-$BUILD_NUMBER.log"
set +e
( cd "$ROOT/app" && npx "$EAS_CLI" submit -p ios --profile production --path "$LOCAL_IPA" --non-interactive ) 2>&1 | tee "$SUBMIT_LOG"
SUBMIT_RC=${PIPESTATUS[0]}
set -e
[ "$SUBMIT_RC" -eq 0 ] || die "eas submit failed (see $SUBMIT_LOG). If it says 401 NOT_AUTHORIZED, the ASC API key stored on EAS needs replacing."
grep -q "Submitted your app to Apple App Store Connect" "$SUBMIT_LOG" || die "eas submit exited 0 but did not confirm the upload (see $SUBMIT_LOG)"

echo "$BUILD_NUMBER" > "$COUNTER"
say "Submitted $VERSION ($BUILD_NUMBER). Updated godot/ios/build-number.txt; commit it with the release-log entry."
