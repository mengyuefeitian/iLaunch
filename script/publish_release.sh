#!/usr/bin/env bash
set -euo pipefail

# Signs a release .dmg with Sparkle's EdDSA key and prints the appcast
# <item> XML to paste into docs/appcast.xml. Manual, per-release — not run
# by CI. Requires the private key generated in Task 6 Step 1 to be present
# in this machine's Keychain.

VERSION="${1:?Usage: publish_release.sh <version> <path-to-dmg>}"
DMG_PATH="${2:?Usage: publish_release.sh <version> <path-to-dmg>}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_UPDATE="$(find "$ROOT_DIR/.build" -name "sign_update" -type f | head -n 1)"

if [ -z "$SIGN_UPDATE" ]; then
  echo "error: sign_update tool not found under .build — run 'swift build --product sign_update' first" >&2
  exit 1
fi

# sign_update's stdout already includes both sparkle:edSignature and length
# attributes — do not add a second length= here, it would produce invalid
# XML (duplicate attribute on the same element).
SIGNATURE_LINE="$("$SIGN_UPDATE" "$DMG_PATH")"
DOWNLOAD_URL="https://github.com/mengyuefeitian/iLaunch/releases/download/v${VERSION}/$(basename "$DMG_PATH")"

cat <<ITEM

Paste this <item> into docs/appcast.xml, inside <channel>, above any older entries:

    <item>
      <title>Version ${VERSION}</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${DOWNLOAD_URL}"
        type="application/octet-stream"
        ${SIGNATURE_LINE} />
    </item>
ITEM
