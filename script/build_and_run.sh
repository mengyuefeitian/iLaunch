#!/usr/bin/env bash
set -euo pipefail

# Use swiftly-installed toolchain (CLT SwiftPM has a linking bug)
SWIFTLY_TOOLCHAIN="$HOME/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin"
if [ -d "$SWIFTLY_TOOLCHAIN" ]; then
  export PATH="$SWIFTLY_TOOLCHAIN:$PATH"
fi

MODE="${1:-run}"
APP_NAME="iLaunch"
BUNDLE_ID="com.ilaunch.iLaunch"
MIN_SYSTEM_VERSION="14.0"

# Stable self-signed identity (see docs/codesigning.md). Ad-hoc signing (`-`)
# gives every build a new cdhash-based designated requirement, which makes
# macOS TCC reset the App Management / Accessibility grants on every update.
SIGN_IDENTITY="${SIGN_IDENTITY:-iLaunch Local Signing}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

# NOTE: no pkill here. This step only rebuilds the bundle on disk — `rm -rf`
# on a running app's bundle is safe on macOS (a running process keeps its own
# handle to the now-unlinked files), and killing by process name can't tell
# a real interactive session (the user's own dist/iLaunch.app, which
# they routinely launch directly to test) from anything else with the same
# name. Four separate "my folders got reset" reports turned out to be this
# script's own `pkill -x iLaunch` + `--verify`'s auto-launched, blank/
# isolated-data overlay replacing the user's live session mid-use. Only the
# modes below that actually intend to relaunch the app kill first, and only
# right before they do so.

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

APP_RESOURCES="$APP_CONTENTS/Resources"
# The bundle's own icon (Finder, Dock before/without a runtime override, DMG
# window) — defaults to the "Icon 2" variant to match the in-app default
# (UserPreferences.appIconStyle = .icon02), not the old "D" artwork.
ICON_SOURCE="$ROOT_DIR/Resources/Icons/icon02.icns"
mkdir -p "$APP_RESOURCES"
if [ -f "$ICON_SOURCE" ]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES/$APP_NAME.icns"
fi
# Runtime icons only: optimized .icns + small thumb_*.png for settings picker.
# Full-size source PNGs live in Resources/Icons/backup/ and are not packaged.
if [ -d "$ROOT_DIR/Resources/Icons" ]; then
  cp "$ROOT_DIR/Resources/Icons/"*.icns "$APP_RESOURCES/" 2>/dev/null || true
  cp "$ROOT_DIR/Resources/Icons/"thumb_*.png "$APP_RESOURCES/" 2>/dev/null || true
fi

# Embed Sparkle.framework — this project has no Xcode project to do this
# automatically, so the framework must be copied and rpath'd by hand.
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
mkdir -p "$APP_FRAMEWORKS"
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build" -type d -name "Sparkle.framework" -path "*macos*" 2>/dev/null | head -n 1)"
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build" -type d -name "Sparkle.framework" 2>/dev/null | head -n 1)"
fi
if [ -n "$SPARKLE_FRAMEWORK" ]; then
  rm -rf "$APP_FRAMEWORKS/Sparkle.framework"
  cp -R "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
else
  echo "error: Sparkle.framework not found under $ROOT_DIR/.build — the app cannot launch without it. Run 'swift build' first." >&2
  exit 1
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>1.12.0</string>
  <key>CFBundleVersion</key>
  <string>1.12.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>SUFeedURL</key>
  <string>https://mengyuefeitian.github.io/iLaunch/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>rBqYZ63t+TCinVotwTkgUM9BFQeTm5DNwxzmiNeYIpo=</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>NSAppleEventsUsageDescription</key>
  <string>iLaunch 需要控制 Finder，以便把需要管理员权限的应用移到废纸篓。</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign inside-out with the stable local identity so the designated requirement
# is `identifier "$BUNDLE_ID" and certificate leaf = H"..."` on every build.
if [ "$SIGN_IDENTITY" != "-" ] && ! security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
  echo "error: code-signing identity \"$SIGN_IDENTITY\" not found in the keychain." >&2
  echo "       Signing ad-hoc would reset users' App Management grant on every update." >&2
  echo "       Recreate it per docs/codesigning.md, or set SIGN_IDENTITY=- to force ad-hoc." >&2
  exit 1
fi

sign_path() {
  codesign --force --sign "$SIGN_IDENTITY" "$1"
}

SPARKLE_B="$APP_FRAMEWORKS/Sparkle.framework/Versions/B"
for item in \
  "$SPARKLE_B/XPCServices/Installer.xpc" \
  "$SPARKLE_B/XPCServices/Downloader.xpc" \
  "$SPARKLE_B/Autoupdate" \
  "$SPARKLE_B/Updater.app" \
  "$APP_FRAMEWORKS/Sparkle.framework"; do
  [ -e "$item" ] && sign_path "$item"
done
sign_path "$APP_BUNDLE"

verify_signature() {
  codesign --verify --deep --strict "$APP_BUNDLE"
  if [ "$SIGN_IDENTITY" != "-" ]; then
    if ! codesign -dr - "$APP_BUNDLE" 2>&1 | grep -q "certificate leaf"; then
      echo "error: designated requirement lacks 'certificate leaf' — grants would not survive updates:" >&2
      codesign -dr - "$APP_BUNDLE" >&2 || true
      exit 1
    fi
  fi
}
verify_signature

# Kills any iLaunch process by name right before (re)launching one of
# our own — only called from modes below that are about to open a new
# instance themselves, never as an unconditional side effect of building.
kill_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.1
  done
}

open_app() {
  kill_running_app
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    kill_running_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    # Used to launch a real (if data-isolated) GUI instance to "smoke test"
    # packaging — which meant an unconditional pkill + a borderless,
    # always-on-top overlay window landing on the user's real desktop every
    # single packaging pass, repeatedly mistaken for real data loss (see the
    # note above `swift build`). `swift build` + `swift test` + the DMG
    # checksum in package_dmg.sh already verify everything this needs to:
    # confirm the binary exists, is executable, and is signed — no GUI.
    [ -x "$APP_BINARY" ] || { echo "missing or non-executable binary: $APP_BINARY" >&2; exit 1; }
    verify_signature
    echo "verify OK: $APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
