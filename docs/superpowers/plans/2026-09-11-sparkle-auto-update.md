# Sparkle Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give iLaunch daily background update checks plus a one-click download/verify/install/relaunch flow via the Sparkle framework.

**Architecture:** Add Sparkle as an SPM dependency, wrap `SPUStandardUpdaterController` in a small `UpdateService`, wire a "Check for Updates…" menu item, and extend the hand-rolled `build_and_run.sh` bundling script to embed `Sparkle.framework` and add the required `Info.plist` keys. Release signing (EdDSA key generation, `sign_update`, `appcast.xml` regeneration) is a manual per-release process, scripted but not CI-automated.

**Tech Stack:** Swift 6.2 (SPM, no Xcode project), AppKit, Sparkle (`sparkle-project/Sparkle`, SPM distribution), Swift Testing (`@Test`/`#expect`).

**Spec:** `docs/superpowers/specs/2026-09-11-auto-update-and-icon-scale-design.md` (section 2, "Auto-update via Sparkle")

## Global Constraints

- App is ad-hoc signed (`codesign --force --deep --sign -` in `script/build_and_run.sh`), no Developer ID / notarization — do not add any step that assumes a Developer ID exists.
- Built via plain `swift build` + `script/build_and_run.sh`, not Xcode — nothing auto-embeds frameworks; embedding must be scripted explicitly.
- `SUFeedURL` = `https://mengyuefeitian.github.io/iLaunch/appcast.xml` (GitHub Pages serving `docs/appcast.xml` on `master`).
- `SUScheduledCheckInterval` = `86400` (daily), `SUEnableAutomaticChecks` = `true`.
- Private EdDSA signing key must never be committed to git.
- No custom update UI — use Sparkle's standard `SPUStandardUpdaterController` alerts.
- Follow `AGENT.md`: bump `CFBundleShortVersionString`/`CFBundleVersion` in `script/build_and_run.sh` and run `cd script && bash build_and_run.sh run` after the feature is complete, before reporting done.

---

### Task 1: Add Sparkle SPM dependency

**Files:**
- Modify: `Package.swift`

**Interfaces:**
- Produces: `import Sparkle` becomes available to any file in the `iLaunch` target.

- [ ] **Step 1: Add the dependency and product**

Edit `Package.swift` to add the Sparkle package dependency and link it into the executable target. Also add the `@rpath` linker flag so the built binary can locate `Sparkle.framework` relative to `Contents/MacOS/../Frameworks` at runtime (Xcode does this automatically for `.xcodeproj` targets; this project has no Xcode project, so it must be set explicitly):

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "iLaunch",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "iLaunch", targets: ["iLaunch"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "iLaunch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/iLaunch",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "iLaunchTests",
            dependencies: ["iLaunch"],
            path: "Tests/iLaunchTests"
        )
    ]
)
```

- [ ] **Step 2: Resolve and build**

Run: `swift package resolve && swift build`
Expected: Package resolves (downloads Sparkle), build succeeds with no errors. This confirms the dependency and linker flag are both valid before any app code references Sparkle.

- [ ] **Step 3: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build: add Sparkle SPM dependency for auto-update"
```

---

### Task 2: `UpdateService` with testable configuration logic

Following the existing `LoginItemService` pattern (pure decision logic separated from the side-effecting call), keep the "what should the updater be configured to" logic pure and testable, separate from actually touching `SPUStandardUpdaterController`.

**Files:**
- Create: `Sources/iLaunch/Services/UpdateService.swift`
- Test: `Tests/iLaunchTests/UpdateServiceTests.swift`

**Interfaces:**
- Produces: `UpdateService.desiredConfiguration` (static, pure) → `(automaticallyChecksForUpdates: Bool, updateCheckInterval: TimeInterval)`.
- Produces: `protocol UpdaterConfigurable` with `var automaticallyChecksForUpdates: Bool { get set }` and `var updateCheckInterval: TimeInterval { get set }`.
- Produces: `UpdateService.configure(_ updater: UpdaterConfigurable)` — applies `desiredConfiguration` to any conforming instance.
- Produces: `final class UpdateService { init(); func checkForUpdates() }` — the real, non-test-covered wrapper around `SPUStandardUpdaterController`.
- Consumes: `Sparkle.SPUStandardUpdaterController`, `Sparkle.SPUUpdater` (from Task 1's dependency).

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import iLaunch

private final class FakeUpdater: UpdaterConfigurable {
    var automaticallyChecksForUpdates = false
    var updateCheckInterval: TimeInterval = 0
}

@Test func desiredConfigurationChecksAutomaticallyOnceDaily() {
    let config = UpdateService.desiredConfiguration
    #expect(config.automaticallyChecksForUpdates == true)
    #expect(config.updateCheckInterval == 86400)
}

@Test func configureAppliesDesiredConfigurationToAnyUpdater() {
    let fake = FakeUpdater()
    UpdateService.configure(fake)
    #expect(fake.automaticallyChecksForUpdates == true)
    #expect(fake.updateCheckInterval == 86400)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpdateServiceTests`
Expected: FAIL to compile — `UpdateService`, `UpdaterConfigurable`, and `desiredConfiguration`/`configure` don't exist yet.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import Sparkle

/// Minimal surface `UpdateService` needs from an updater, so the
/// configuration logic below can be tested without touching Sparkle's real
/// `SPUUpdater` (which requires a live app host and network access).
protocol UpdaterConfigurable: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
}

extension SPUUpdater: UpdaterConfigurable {}

/// Wraps Sparkle's standard updater controller: daily background checks
/// plus an on-demand check for the "Check for Updates…" menu item. All
/// download/verify/install/relaunch UI is Sparkle's own standard alerts —
/// this type owns no UI itself.
@MainActor
final class UpdateService {
    /// One check per day, started automatically at launch.
    static let desiredConfiguration: (automaticallyChecksForUpdates: Bool, updateCheckInterval: TimeInterval) =
        (automaticallyChecksForUpdates: true, updateCheckInterval: 86400)

    static func configure(_ updater: UpdaterConfigurable) {
        updater.automaticallyChecksForUpdates = desiredConfiguration.automaticallyChecksForUpdates
        updater.updateCheckInterval = desiredConfiguration.updateCheckInterval
    }

    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        Self.configure(controller.updater)
    }

    /// Manual trigger for the "Check for Updates…" menu item.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UpdateServiceTests`
Expected: PASS — both tests green. (This only exercises the pure `desiredConfiguration`/`configure` logic via `FakeUpdater`; it does not instantiate `SPUStandardUpdaterController`, which would require a running app host.)

- [ ] **Step 5: Run the full test suite to confirm no regressions**

Run: `swift test`
Expected: All existing tests plus the 2 new ones pass (116 total).

- [ ] **Step 6: Commit**

```bash
git add Sources/iLaunch/Services/UpdateService.swift Tests/iLaunchTests/UpdateServiceTests.swift
git commit -m "feat: add UpdateService wrapping Sparkle's standard updater"
```

---

### Task 3: Wire `UpdateService` into app lifecycle

**Files:**
- Modify: `Sources/iLaunch/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `UpdateService()` (Task 2), `MenuBarController.init(overlay:hotKeyManager:updateService:)` (Task 4 — this task passes it through, Task 4 defines the new parameter).

- [ ] **Step 1: Instantiate `UpdateService` at launch**

In `Sources/iLaunch/App/AppDelegate.swift`, add a property and instantiate it in `applicationDidFinishLaunching`, alongside the other launch-time services (after `LoginItemService.apply`, before `hotKeyManager` setup — order doesn't matter functionally, but keeps related setup grouped):

```swift
private var menuBarController: MenuBarController?
private var hotKeyManager: GlobalHotKeyManager?
private var updateService: UpdateService?
```

```swift
        LoginItemService.apply(prefs.launchAtLogin)
        updateService = UpdateService()
```

Then update the `MenuBarController` construction line to pass it through:

```swift
        menuBarController = MenuBarController(overlay: overlay, hotKeyManager: hotKeyManager, updateService: updateService)
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `swift build`
Expected: FAILS at this point — `MenuBarController.init` doesn't yet accept `updateService:`. This is expected; Task 4 adds that parameter. Do not attempt to make this task build in isolation — Tasks 3 and 4 are interdependent by design (both touch the same initializer call site) and are verified together at the end of Task 4.

- [ ] **Step 3: Commit (staged together with Task 4 — see Task 4 Step 5)**

No standalone commit here; this task's change is committed together with Task 4's `MenuBarController` change once both compile.

---

### Task 4: "Check for Updates…" menu item

**Files:**
- Modify: `Sources/iLaunch/Services/MenuBarController.swift`
- Modify: `Sources/iLaunch/Support/Localizer.swift`

**Interfaces:**
- Consumes: `UpdateService.checkForUpdates()` (Task 2).
- Produces: `MenuBarController.init(overlay:hotKeyManager:updateService:)` — new required parameter, called from Task 3.

- [ ] **Step 1: Add localized strings**

In `Sources/iLaunch/Support/Localizer.swift`, add `"menubar.checkForUpdates"` next to each existing `"menubar.logs"` entry, one per language dictionary:

```swift
// enStrings, after "menubar.logs": "Open Log File",
"menubar.checkForUpdates": "Check for Updates…",
```
```swift
// zhStrings, after "menubar.logs": "打开日志文件",
"menubar.checkForUpdates": "检查更新…",
```
```swift
// jaStrings, after "menubar.logs": "ログファイルを開く",
"menubar.checkForUpdates": "アップデートを確認…",
```
```swift
// koStrings, after "menubar.logs": "로그 파일 열기",
"menubar.checkForUpdates": "업데이트 확인…",
```
```swift
// ruStrings, after "menubar.logs": "Открыть файл журнала",
"menubar.checkForUpdates": "Проверить обновления…",
```

- [ ] **Step 2: Add the menu item to `MenuBarController`**

In `Sources/iLaunch/Services/MenuBarController.swift`, add the stored properties and constructor parameter:

```swift
private weak var hotKeyManager: GlobalHotKeyManager?
private let settings = SettingsWindowController()
private let updateService: UpdateService?
```

```swift
private var settingsItem: NSMenuItem!
private var logsItem: NSMenuItem!
private var checkForUpdatesItem: NSMenuItem!
private var quitItem: NSMenuItem!

init(overlay: OverlayWindowController, hotKeyManager: GlobalHotKeyManager?, updateService: UpdateService?) {
    self.overlay = overlay
    self.hotKeyManager = hotKeyManager
    self.updateService = updateService
    super.init()
```

Add the item to the menu, right after `logsItem` and before the separator:

```swift
        logsItem = NSMenuItem(title: "", action: #selector(openLogs), keyEquivalent: "")
        logsItem.target = self
        statusMenu.addItem(logsItem)

        checkForUpdatesItem = NSMenuItem(title: "", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.target = self
        statusMenu.addItem(checkForUpdatesItem)

        statusMenu.addItem(NSMenuItem.separator())
```

Add the title refresh:

```swift
    private func refreshMenuTitles() {
        settingsItem.title = Localizer.t("menubar.settings")
        logsItem.title = Localizer.t("menubar.logs")
        checkForUpdatesItem.title = Localizer.t("menubar.checkForUpdates")
        quitItem.title = Localizer.t("menubar.quit")
    }
```

Add the action, near the other `@objc` handlers (e.g. `openLogs`):

```swift
    @objc private func checkForUpdates() {
        updateService?.checkForUpdates()
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: SUCCESS — Task 3's call site now matches this initializer.

- [ ] **Step 4: Manual smoke check**

Run: `cd script && bash build_and_run.sh run`, then click the menu bar icon → confirm "Check for Updates…" appears (localized text, English by default in a non-Chinese system locale) between "Open Log File" and the separator, and clicking it doesn't crash (it will attempt a real network check against a not-yet-published feed URL — Sparkle will show its standard "check failed" alert, which is expected until Task 6/7's feed exists; confirm the app doesn't crash and the alert is dismissable).

- [ ] **Step 5: Commit (Tasks 3 + 4 together)**

```bash
git add Sources/iLaunch/App/AppDelegate.swift Sources/iLaunch/Services/MenuBarController.swift Sources/iLaunch/Support/Localizer.swift
git commit -m "feat: add Check for Updates menu item wired to UpdateService"
```

---

### Task 5: Embed `Sparkle.framework` in the app bundle

**Files:**
- Modify: `script/build_and_run.sh`

**Interfaces:**
- Consumes: Task 1's SPM dependency (the built `Sparkle.framework` artifact under `.build/`).

- [ ] **Step 1: Locate the built framework**

Run: `swift build` (if not already built from Task 1), then locate the framework:

```bash
find .build -type d -name "Sparkle.framework"
```

Expected: exactly one path, typically under `.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework` (the exact path depends on the resolved Sparkle version and host architecture — confirm the actual path printed by `find` before hardcoding it in the script below).

- [ ] **Step 2: Add the embed step to `build_and_run.sh`**

In `script/build_and_run.sh`, after the existing icon-copying block (after `cp "$ROOT_DIR/Resources/Icons/"thumb_*.png ...` and before the `cat >"$INFO_PLIST"` heredoc), add:

```bash
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
  echo "warning: Sparkle.framework not found under $ROOT_DIR/.build — auto-update will not work in this build" >&2
fi
```

Place this before the existing `codesign --force --deep --sign - "$APP_BUNDLE"` line so the embedded framework gets ad-hoc signed along with the rest of the bundle (`--deep` already recurses into `Contents/Frameworks`).

- [ ] **Step 3: Build and verify embedding**

Run: `cd script && bash build_and_run.sh run`
Expected: no "warning: Sparkle.framework not found" message; `ls dist/iLaunch.app/Contents/Frameworks/Sparkle.framework` shows the embedded framework contents.

Run: `otool -L dist/iLaunch.app/Contents/MacOS/iLaunch | grep Sparkle`
Expected: a line referencing `@rpath/Sparkle.framework/Versions/.../Sparkle`, confirming Task 1's linker rpath flag resolved correctly against the embedded copy.

- [ ] **Step 4: Commit**

```bash
git add script/build_and_run.sh
git commit -m "build: embed Sparkle.framework into the app bundle"
```

---

### Task 6: `Info.plist` Sparkle keys + EdDSA key generation

**Files:**
- Modify: `script/build_and_run.sh`

**Interfaces:**
- Produces: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval` keys in the generated `Info.plist`.

- [ ] **Step 1: Generate the EdDSA key pair (manual, one-time — run by you, not committed by this task)**

The Sparkle SPM package vends a `generate_keys` CLI tool as a plugin/executable. After Task 1's `swift package resolve`, locate and run it:

```bash
swift build --product generate_keys 2>/dev/null || find .build -name "generate_keys" -type f
```

Run the located `generate_keys` binary with no arguments. It prints a public key (base64 EdDSA key, ~44 characters ending in `=`) and stores the private key in your macOS Keychain under the service name it reports (Sparkle's default: `https://sparkle-project.org` / account `ed25519`). **Copy the printed public key** — it goes into Step 2 below.

**Deviation from macOS Keychain (ruling, recorded 2026-09-11):** the user explicitly rejected using macOS Keychain for private key storage. Export the private key out of Keychain to a plain, owner-only file, then remove it from Keychain entirely:

```bash
mkdir -p "$HOME/.config/ilaunch"
generate_keys -x "$HOME/.config/ilaunch/sparkle_signing_key"
chmod 600 "$HOME/.config/ilaunch/sparkle_signing_key"
security delete-generic-password -s "https://sparkle-project.org" -a "ed25519"
```

From this point on, signing uses `sign_update -f "$HOME/.config/ilaunch/sparkle_signing_key"` (see Task 7's `publish_release.sh`, which reads this path from `SPARKLE_PRIVATE_KEY_FILE`, defaulting to `$HOME/.config/ilaunch/sparkle_signing_key`). The public key and its Info.plist value are unaffected by this change — only the private key's storage location changes. The private key file itself must never be committed or leave this machine ungoverned; back it up to a password manager or encrypted volume if you need a second copy, not to git.

- [ ] **Step 2: Add the Sparkle keys to `Info.plist`**

In `script/build_and_run.sh`, inside the existing `cat >"$INFO_PLIST" <<PLIST` heredoc, add these keys (placed after the existing `LSMinimumSystemVersion` entry):

```xml
  <key>SUFeedURL</key>
  <string>https://mengyuefeitian.github.io/iLaunch/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>PASTE_THE_PUBLIC_KEY_FROM_STEP_1_HERE</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
```

The public key is not a secret — it's safe to commit verbatim in the script.

- [ ] **Step 3: Build and verify**

Run: `cd script && bash build_and_run.sh run`
Run: `/usr/libexec/PlistBuddy -c "Print :SUFeedURL" dist/iLaunch.app/Contents/Info.plist`
Expected: prints `https://mengyuefeitian.github.io/iLaunch/appcast.xml`.
Run: `/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" dist/iLaunch.app/Contents/Info.plist`
Expected: prints the same public key from Step 1 (not the placeholder text).

- [ ] **Step 4: Commit**

```bash
git add script/build_and_run.sh
git commit -m "build: configure Sparkle feed URL and public key in Info.plist"
```

---

### Task 7: Release signing script + appcast scaffold

**Files:**
- Create: `script/publish_release.sh`
- Create: `docs/appcast.xml`

**Interfaces:**
- Consumes: `script/package_dmg.sh` (existing — produces the `.dmg` this script signs), the `sign_update` and `generate_appcast` Sparkle SPM tools (same artifact location pattern as `generate_keys` in Task 6).

- [ ] **Step 1: Create an initial empty appcast**

Create `docs/appcast.xml` with a minimal valid RSS/Sparkle appcast shell (no `<item>` entries yet — the first real release populates one):

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>iLaunch Updates</title>
    <link>https://mengyuefeitian.github.io/iLaunch/appcast.xml</link>
    <description>Most recent updates for iLaunch.</description>
    <language>en</language>
  </channel>
</rss>
```

- [ ] **Step 2: Write the release-signing script**

Create `script/publish_release.sh` — takes a version and a built `.dmg` path, signs it, and prints the `<item>` block to paste into `docs/appcast.xml` (kept manual/copy-paste per the spec's decision not to fully automate this into CI):

```bash
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
SIGN_UPDATE="$(find "$ROOT_DIR/.build" -name "sign_update" -type f | head -n 1)"

if [ -z "$SIGN_UPDATE" ]; then
  echo "error: sign_update tool not found under .build — run 'swift package resolve' first" >&2
  exit 1
fi

# sign_update's stdout already includes both sparkle:edSignature and length
# attributes — do not add a second length= here, it would produce invalid
# XML (duplicate attribute on the same element).
SIGNATURE_LINE="$("$SIGN_UPDATE" -f "$SPARKLE_PRIVATE_KEY_FILE" "$DMG_PATH")"
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
```

(This reflects the fix-round correction to the original duplicate-`length=` bug and the Keychain→file ruling, both applied during execution — see the SDD ledger.)

- [ ] **Step 3: Make it executable and verify it runs**

Run: `chmod +x script/publish_release.sh`
Run: `swift package resolve`
Run: `./script/publish_release.sh 1.8.11 dist/iLaunch.dmg` (using whatever `.dmg` `package_dmg.sh` last produced, or run `bash script/package_dmg.sh` first if none exists)
Expected: prints an `<item>` block with a real `sparkle:edSignature` attribute inside `${SIGNATURE_LINE}` — confirms the file-based private key from Task 6 Step 1 is being found and used.

- [ ] **Step 4: Commit**

```bash
git add script/publish_release.sh docs/appcast.xml
git commit -m "build: add release-signing script and appcast scaffold"
```

---

### Task 8: Enable GitHub Pages (manual, user-owned)

Not a code task — flagged per the spec's "Ask first" boundary.

- [ ] **Step 1: Ask the user to confirm/enable GitHub Pages**

Before relying on `https://mengyuefeitian.github.io/iLaunch/appcast.xml` resolving, confirm with the user that GitHub Pages is enabled for `mengyuefeitian/iLaunch`, serving from the `master` branch `/docs` folder (Settings → Pages → Source). This is a repo-settings change, not a code change — do not attempt it via `gh` without the user's explicit go-ahead, per the design's "Ask first" boundary.

---

### Task 9: End-to-end manual verification

Not unit-testable — Sparkle's actual network check, download, signature verification, and relaunch require a real published appcast and a real older build to update from.

- [ ] **Step 1: Full regression run**

Run: `swift test`
Expected: all tests pass (116 from before this plan + the 2 new `UpdateServiceTests` = 118).

- [ ] **Step 2: Version bump and build per `AGENT.md`**

Bump `CFBundleShortVersionString`/`CFBundleVersion` in `script/build_and_run.sh` (minor bump — this is a new feature) and run `cd script && bash build_and_run.sh run`.

- [ ] **Step 3: Manual update-flow check (requires Task 8 complete and at least one prior tagged release published)**

Install an older tagged build, then with the new build's binary confirm: menu bar → "Check for Updates…" → Sparkle finds the newer version from the live appcast → shows release notes and an "Install Update" button → one click downloads, verifies the EdDSA signature, unpacks, and relaunches into the new version automatically, with no further clicks. This step can only run once a real release with a signed `.dmg` and populated `docs/appcast.xml` entry (Task 7) exists — it is the final acceptance check for the whole feature, not something achievable during initial implementation.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: vX.Y.Z — Sparkle auto-update"
```
