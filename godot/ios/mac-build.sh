#!/usr/bin/env bash
# Mac-side half of the Godot iOS pipeline. Normally launched (detached, with nohup)
# by scripts/ship-ios-godot.sh on the Linux box; it can also be run by hand on the Mac.
#
#   mac-build.sh --work <dir> --src <godot project dir> --build-number <N> [--version 0.3.0] [--unsigned]
#
# <src> is the godot/ folder to build: ~/dev/wildbound/godot after a git pull, or a
# copy of the local working tree rsynced over (ship-ios-godot.sh --sync-local).
# <dir> is a private temp dir. In signed mode it must contain:
#   dist.p12            distribution certificate (from EAS)
#   dist.p12.password   its password (one line)
#   profile.mobileprovision   App Store provisioning profile for com.taiga.wildbound
#
# Signed mode: imports the certificate into a throwaway keychain (random password,
# never the login keychain), installs the profile, has Godot write the Xcode project
# (export_project_only), then runs xcodebuild archive + -exportArchive itself and
# leaves the ipa in <dir>/out/. Unsigned mode stops after an unsigned xcodebuild archive with
# CODE_SIGNING_ALLOWED=NO, to prove Godot + templates + Xcode compile.
#
# The staged copy of the project lives in ~/wildbound-build/godot (keeps Godot's
# import cache between runs); the git checkout itself is never modified.
#
# The result is written to <dir>/status: "ok <path>" or "fail <reason>".
# The keychain and the certificate files are always deleted on exit.
set -uo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
GODOT="${GODOT:-godot}"
GODOT_VERSION="4.7.2.stable.official.ed1daf0bf"
BUILD_DIR="${WILDBOUND_BUILD_DIR:-$HOME/wildbound-build}"   # persistent: keeps Godot's import cache
PRESET="iOS"
APP_NAME="Wildbound"
BUNDLE_ID="com.taiga.wildbound"
TEAM_ID="6R43H3SA48"

WORK=""; SRC=""; BUILD_NUMBER=""; VERSION="0.3.0"; UNSIGNED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK="$2"; shift 2 ;;
    --src) SRC="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --unsigned) UNSIGNED=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "--work <existing dir> is required" >&2; exit 2; }
[ -n "$SRC" ] && [ -f "$SRC/project.godot" ] || { echo "--src <godot project dir> is required" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "--build-number <integer> is required" >&2; exit 2; }

STATUS="$WORK/status"
KC=""; OLD_KEYCHAINS=()
log() { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { log "FAILED: $*"; echo "fail $*" > "$STATUS"; exit 1; }

cleanup() {
  if [ -n "$KC" ]; then
    if [ ${#OLD_KEYCHAINS[@]} -gt 0 ]; then
      security list-keychains -d user -s "${OLD_KEYCHAINS[@]}" >/dev/null 2>&1
    fi
    security delete-keychain "$KC" >/dev/null 2>&1 && log "temp keychain deleted"
  fi
  rm -f "$WORK/dist.p12" "$WORK/dist.p12.password" "$WORK/kc.pw"
  [ -f "$STATUS" ] || echo "fail interrupted" > "$STATUS"
}
trap cleanup EXIT
trap 'fail "killed by signal"' INT TERM HUP

log "Wildbound iOS build: version $VERSION ($BUILD_NUMBER), $([ $UNSIGNED = 1 ] && echo unsigned || echo signed)"
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  log "source $SRC at $(git -C "$SRC" rev-parse --short HEAD): $(git -C "$SRC" log -1 --format=%s)"
else
  log "source $SRC (not a git checkout: local working tree sync)"
fi

command -v "$GODOT" >/dev/null || fail "godot not on PATH (expected /usr/local/bin/godot)"
GV="$("$GODOT" --version 2>/dev/null | tail -1)"
[ "$GV" = "$GODOT_VERSION" ] || fail "godot version is '$GV', expected $GODOT_VERSION"
TPL="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/ios.zip"
[ -f "$TPL" ] || fail "iOS export template missing: $TPL"
log "xcode: $(xcodebuild -version | tr '\n' ' ')"

# --- signing: temp keychain + provisioning profile -------------------------------
SIGN_ID=""; PROFILE_UUID=""
if [ $UNSIGNED = 0 ]; then
  for f in dist.p12 dist.p12.password profile.mobileprovision; do
    [ -f "$WORK/$f" ] || fail "missing $WORK/$f (credentials were not copied over)"
  done
  KC="$WORK/wildbound-signing.keychain-db"
  KCPW="$(openssl rand -hex 24)"
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
    [ -n "$line" ] && OLD_KEYCHAINS+=("$line")
  done < <(security list-keychains -d user)
  security create-keychain -p "$KCPW" "$KC" || fail "create-keychain"
  security set-keychain-settings -lut 7200 "$KC"
  security unlock-keychain -p "$KCPW" "$KC" || fail "unlock-keychain"
  security import "$WORK/dist.p12" -k "$KC" -f pkcs12 -P "$(cat "$WORK/dist.p12.password")" \
    -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild >/dev/null \
    || fail "importing dist.p12 (wrong password in credentials.json?)"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null \
    || fail "set-key-partition-list"
  security list-keychains -d user -s "$KC" "${OLD_KEYCHAINS[@]}"
  rm -f "$WORK/dist.p12" "$WORK/dist.p12.password"

  # The distribution cert chains to a WWDR intermediate (G3 today). It is in the login
  # keychain on this Mac, but put current ones in the temp keychain too so the chain
  # never depends on that. Best effort: a download failure is not fatal.
  for g in G3 G6; do
    if curl -fsS -m 20 -o "$WORK/wwdr$g.cer" "https://www.apple.com/certificateauthority/AppleWWDRCA$g.cer"; then
      security import "$WORK/wwdr$g.cer" -k "$KC" >/dev/null 2>&1 || true
    fi
  done
  IDS="$(security find-identity -v -p codesigning "$KC")"
  echo "$IDS"
  SIGN_ID="$(echo "$IDS" | sed -nE 's/^ *[0-9]+\) [0-9A-F]{40} "((Apple|iPhone) Distribution: [^"]+)".*/\1/p' | head -1)"
  [ -n "$SIGN_ID" ] || fail "no valid Apple/iPhone Distribution identity in the p12 (expired, or WWDR intermediate missing?)"
  echo "$SIGN_ID" | grep -q "($TEAM_ID)" || fail "identity '$SIGN_ID' is not for team $TEAM_ID"
  log "signing identity: $SIGN_ID"

  PLIST="$WORK/profile.plist"
  security cms -D -i "$WORK/profile.mobileprovision" > "$PLIST" 2>/dev/null || fail "cannot decode the provisioning profile"
  pb() { /usr/libexec/PlistBuddy -c "Print $1" "$PLIST" 2>/dev/null; }
  PROFILE_UUID="$(pb :UUID)"
  APPID="$(pb :Entitlements:application-identifier)"
  EXPIRES="$(pb :ExpirationDate)"
  [ "$APPID" = "$TEAM_ID.$BUNDLE_ID" ] || fail "profile is for '$APPID', expected $TEAM_ID.$BUNDLE_ID"
  [ "$(pb :Entitlements:get-task-allow)" = "false" ] || fail "profile allows get-task-allow: it is a development profile, not App Store"
  pb :ProvisionedDevices >/dev/null && fail "profile lists devices: it is ad-hoc/development, not App Store"
  log "profile: $(pb :Name) uuid=$PROFILE_UUID expires=$EXPIRES"
  for d in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    mkdir -p "$d" && cp "$WORK/profile.mobileprovision" "$d/$PROFILE_UUID.mobileprovision"
  done
fi

# --- stage the project into the persistent build dir -----------------------------
# Building from a copy keeps the git checkout clean (no preset edits, no .godot churn
# from the export) so the next `git pull --ff-only` always works.
mkdir -p "$BUILD_DIR"
rsync -a --delete --exclude .godot/ --exclude build/ "$SRC/" "$BUILD_DIR/godot/" || fail "rsync"
P="$BUILD_DIR/godot"
python3 - "$P/export_presets.cfg" "$VERSION" "$BUILD_NUMBER" "$UNSIGNED" "$SIGN_ID" "$PROFILE_UUID" <<'EOF' || fail "patching export_presets.cfg"
import re, sys
path, version, build, unsigned, sign_id, uuid = sys.argv[1:]
s = open(path).read()
def setopt(key, value):
    global s
    line = f'{key}={value}'
    pat = re.compile('^' + re.escape(key) + '=.*$', re.M)
    if pat.search(s):
        s = pat.sub(lambda m: line, s, count=1)
    else:
        s = s.replace('[preset.0.options]\n', '[preset.0.options]\n\n' + line + '\n', 1)
setopt('application/short_version', f'"{version}"')
setopt('application/version', f'"{build}"')
# Godot writes the Xcode project only; this script runs xcodebuild itself (clear
# errors, explicit keychain, explicit export options instead of Godot's built-in ones).
setopt('application/export_project_only', 'true')
if unsigned != '1':
    setopt('application/code_sign_identity_release', f'"{sign_id}"')
    setopt('application/provisioning_profile_uuid_release', f'"{uuid}"')
open(path, 'w').write(s)

# iOS export refuses to run (silently: "configuration errors:" with no text) unless
# ETC2/ASTC texture import is on. Enforce it in the staged copy if project.godot lacks it.
proj = path.replace('export_presets.cfg', 'project.godot')
p = open(proj).read()
key = 'textures/vram_compression/import_etc2_astc=true'
if key not in p:
    if '\n[rendering]\n' in p:
        p = p.replace('\n[rendering]\n', '\n[rendering]\n\n' + key + '\n', 1)
    else:
        p = p.rstrip('\n') + '\n\n[rendering]\n\n' + key + '\n'
    open(proj, 'w').write(p)
    print('note: enabled ' + key + ' in the staged project.godot (add it to godot/project.godot)')
EOF

OUT="$WORK/out"; rm -rf "$OUT"; mkdir -p "$OUT"
cd "$P"
log "importing assets"
"$GODOT" --headless --path "$P" --import > "$WORK/import.log" 2>&1
grep -E "ERROR|SCRIPT ERROR" "$WORK/import.log" | head -20

log "godot export ($PRESET): Xcode project -> $OUT/$APP_NAME.xcodeproj"
"$GODOT" --headless --path "$P" --export-release "$PRESET" "$OUT/$APP_NAME.ipa"
GRC=$?
log "godot exit code $GRC"
[ $GRC -eq 0 ] && [ -d "$OUT/$APP_NAME.xcodeproj" ] || fail "Godot export failed (exit $GRC); see the Godot output above"

if [ $UNSIGNED = 1 ]; then
  log "xcodebuild archive (unsigned, generic iOS device)"
  xcodebuild -project "$OUT/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -sdk iphoneos \
    -configuration Release -destination "generic/platform=iOS" -archivePath "$OUT/$APP_NAME.xcarchive" \
    -derivedDataPath "$OUT/DerivedData" CODE_SIGNING_ALLOWED=NO archive > "$WORK/xcodebuild.log" 2>&1
  grep -E "error:|\*\* ARCHIVE" "$WORK/xcodebuild.log" | tail -40
  APP="$(ls -d "$OUT/$APP_NAME.xcarchive"/Products/Applications/*.app 2>/dev/null | head -1)"
  [ -n "$APP" ] || { tail -40 "$WORK/xcodebuild.log"; fail "xcodebuild archive did not produce an .app"; }
  log "built $APP"
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" "$APP/Info.plist"
  echo "ok $APP" > "$STATUS"
  exit 0
fi

log "xcodebuild archive (manual signing: $SIGN_ID, profile $PROFILE_UUID)"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
xcodebuild -project "$OUT/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -sdk iphoneos \
  -configuration Release -destination "generic/platform=iOS" -archivePath "$ARCHIVE" \
  -derivedDataPath "$OUT/DerivedData" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$SIGN_ID" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" OTHER_CODE_SIGN_FLAGS="--keychain $KC" \
  archive > "$WORK/xcodebuild.log" 2>&1
grep -E "error:|\*\* ARCHIVE" "$WORK/xcodebuild.log" | tail -40
grep -q "\*\* ARCHIVE SUCCEEDED \*\*" "$WORK/xcodebuild.log" || { tail -40 "$WORK/xcodebuild.log"; fail "xcodebuild archive failed"; }

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$SIGN_ID</string>
  <key>provisioningProfiles</key>
  <dict><key>$BUNDLE_ID</key><string>$PROFILE_UUID</string></dict>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
log "xcodebuild -exportArchive"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$OUT/export" > "$WORK/export.log" 2>&1
grep -E "error:|\*\* EXPORT" "$WORK/export.log" | tail -20
IPA="$(ls "$OUT"/export/*.ipa 2>/dev/null | head -1)"
[ -n "$IPA" ] || { tail -40 "$WORK/export.log"; fail "xcodebuild -exportArchive produced no ipa"; }

# --- verify what we are about to hand back ---------------------------------------
V="$WORK/verify"; rm -rf "$V"; mkdir -p "$V"
unzip -q "$IPA" -d "$V" || fail "ipa is not a valid zip"
APP="$(ls -d "$V"/Payload/*.app | head -1)"
INFO="$APP/Info.plist"
GOT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
GOT_V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
GOT_B="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")"
log "ipa Info.plist: $GOT_ID $GOT_V ($GOT_B)"
[ "$GOT_ID" = "$BUNDLE_ID" ] || fail "bundle id is $GOT_ID"
[ "$GOT_V" = "$VERSION" ] && [ "$GOT_B" = "$BUILD_NUMBER" ] || fail "version mismatch in ipa"
codesign -dvv "$APP" 2>&1 | grep -E "^(Authority|TeamIdentifier)=" | head -2
codesign --verify --strict "$APP" || fail "codesign verification failed"
rm -rf "$V"

FINAL="$OUT/$APP_NAME-$VERSION-$BUILD_NUMBER.ipa"
mv "$IPA" "$FINAL"
log "ipa ready: $FINAL ($(du -h "$FINAL" | cut -f1))"
echo "ok $FINAL" > "$STATUS"
