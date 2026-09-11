#!/usr/bin/env bash
set -euo pipefail

# Signs a release .dmg with Sparkle's EdDSA key and prints the appcast
# <item> XML to paste into docs/appcast.xml. Manual, per-release — not run
# by CI. Requires the private key file exported in Task 6 Step 1
# (generate_keys -x) to be present at SPARKLE_PRIVATE_KEY_FILE. Deliberately
# not Keychain-based: the private key lives only in a plain, owner-only file
# outside git, never in macOS Keychain.

VERSION="${1:?Usage: publish_release.sh <version> <path-to-dmg>}"
DMG_PATH="${2:?Usage: publish_release.sh <version> <path-to-dmg>}"

SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$HOME/.config/ilaunch/sparkle_signing_key}"
if [ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]; then
  echo "error: private key file not found at $SPARKLE_PRIVATE_KEY_FILE — set SPARKLE_PRIVATE_KEY_FILE or run 'generate_keys -x <file>' first" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Prefer the known-correct EdDSA sign_update path (Sparkle ships it
# pre-built inside the resolved package artifacts — it is not an SPM
# product, so it can't be built with `swift build --product sign_update`).
# Fall back to a find-based search (excluding the legacy DSA bash script at
# old_dsa_scripts/sign_update, which takes different arguments) in case the
# exact path shifts in a future Sparkle version.
SIGN_UPDATE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ ! -f "$SIGN_UPDATE" ]; then
  SIGN_UPDATE="$(find "$ROOT_DIR/.build" -name "sign_update" -type f -not -path "*old_dsa_scripts*" | head -n 1)"
fi

if [ -z "$SIGN_UPDATE" ] || [ ! -f "$SIGN_UPDATE" ]; then
  echo "error: sign_update tool not found under .build — run 'swift package resolve' first" >&2
  exit 1
fi

# sign_update's stdout already includes both sparkle:edSignature and length
# attributes — do not add a second length= here, it would produce invalid
# XML (duplicate attribute on the same element).
SIGNATURE_LINE="$("$SIGN_UPDATE" -f "$SPARKLE_PRIVATE_KEY_FILE" "$DMG_PATH")"
DOWNLOAD_URL="https://github.com/mengyuefeitian/iLaunch/releases/download/v${VERSION}/$(basename "$DMG_PATH")"

# Derive minimumSystemVersion from the actual built app bundle's
# Info.plist rather than hardcoding it — the built binary's real minimum
# OS requirement (from Package.swift's platform setting) is the only
# reliable source of truth, and a stale hardcoded value could cause
# Sparkle to offer an update to machines that can't run it.
APP_BUNDLE="$ROOT_DIR/dist/iLaunch.app"
APP_INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
if [ ! -d "$APP_BUNDLE" ]; then
  echo "error: $APP_BUNDLE not found — build the app first with 'bash script/build_and_run.sh' before running publish_release.sh" >&2
  exit 1
fi
MIN_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP_INFO_PLIST" 2>/dev/null || true)"
if [ -z "$MIN_SYSTEM_VERSION" ]; then
  echo "error: LSMinimumSystemVersion not found in $APP_INFO_PLIST — ensure the app was built via 'bash script/build_and_run.sh' first" >&2
  exit 1
fi

cat <<ITEM

Paste this <item> into docs/appcast.xml, inside <channel>, above any older entries:

    <item>
      <title>Version ${VERSION}</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <enclosure
        url="${DOWNLOAD_URL}"
        type="application/octet-stream"
        ${SIGNATURE_LINE} />
    </item>
ITEM
