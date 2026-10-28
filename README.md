# macmoji

A macOS menu-bar utility that gives Slack-style `:` emoji autocomplete in any app.
Type `:` and a couple of letters (`:thu`) and a small picker pops up next to the text cursor;
↑/↓ to choose, Enter or Tab to insert, Esc to dismiss. The typed `:shortcode` is replaced with
the emoji. Typing a full `:fire:` replaces it automatically.

Status: **M1 prototype.** The core logic is unit-tested; the macOS app code has not yet been
compiled or run (it was written on Linux). See [TESTING.md](TESTING.md) and the
plan in [docs/PLAN.md](docs/PLAN.md).

- macOS 14+, menu bar only (no Dock icon), not sandboxed, not for the App Store.
- One permission: **Accessibility**.
- Off by default in Slack and Discord (they have their own picker); never active in password
  fields / while secure input is on.
- Emoji data: [emojibase-data](https://github.com/milesj/emojibase) v18 (MIT), Slack (iamcal)
  shortcodes first, GitHub names as aliases, emojibase tags as search keywords.

## Layout
```
project.yml                  XcodeGen spec (the .xcodeproj is generated, not committed)
Config/Signing.xcconfig      signing defaults; put your team in Config/Signing.local.xcconfig
App/Sources/                 the macOS app (AppKit / SwiftUI / ApplicationServices / CoreGraphics)
App/Resources/               Info.plist (LSUIElement), entitlements (no sandbox)
MacmojiCore/                 portable Swift package: emoji data, search & ranking, trigger state machine + tests
scripts/make-dmg.sh          builds dist/Macmoji-<version>.dmg
packaging/                   DMG background art, icon generator, previews
scripts/gen-emoji.mjs        regenerates MacmojiCore/.../Resources/emoji.json from emojibase-data
.github/workflows/ci.yml     macOS CI: generate, build, test
```

## Installing
1. Open `Macmoji-<version>.dmg` (from a GitHub Actions artifact/release, or built with
   `scripts/make-dmg.sh`).
2. Drag **Macmoji** onto the **Applications** folder in the window that appears.
3. Eject the disk image, then open Macmoji from Applications. If the DMG wasn't notarized,
   macOS will block the first launch: right-click Macmoji → **Open**, or allow it in System
   Settings → Privacy & Security (or `xattr -dr com.apple.quarantine /Applications/Macmoji.app`).
4. The setup window walks you through skin tone, launch at login and the Accessibility
   permission. Then type `:thu` anywhere.

## Build and run on a Mac
Requirements: macOS 14+, Xcode 15.3+ (Swift 5.10+), Homebrew.

```sh
brew install xcodegen
git clone https://github.com/trev-org/macmoji.git && cd macmoji
# (recommended) set up signing first, see "Signing" below
xcodegen generate
open Macmoji.xcodeproj
```
In Xcode pick the **Macmoji** scheme and **My Mac**, then Run (⌘R). A smiley appears in the
menu bar. Or from the command line:
```sh
xcodebuild -project Macmoji.xcodeproj -scheme Macmoji -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Macmoji.app
```
Unit tests: `cd MacmojiCore && swift test`.

Always test the bundled `Macmoji.app`. Running core code through `swift run` or a terminal
would attribute permissions to Terminal instead.

## First-run setup
On first launch macmoji opens a setup window **before it captures anything** (the event tap
does not start until setup is finished). Steps, with Back/Next:
1. **Default skin tone**: pick one of six 👋 variants (saved to the skin-tone setting).
2. **Launch at login**: yes/no toggle using `SMAppService.mainApp`. If macOS answers
   "requires approval", a button opens System Settings → General → Login Items.
3. **Accessibility** (see below). The step moves on by itself once access is granted.
4. **You're all set**: try `:thu`. Clicking *Start using macmoji* saves the
   `onboardingCompleted` flag and starts the app.

If you close or quit setup partway, it shows again next launch. After it's finished, later
launches go straight to running. Menu bar → **Run setup again…** reopens it. To force a fresh
first run: `defaults delete com.trevorgerald.macmoji onboardingCompleted`.

## Granting Accessibility
In the setup's Accessibility step (or, if the grant is later revoked, the
"macmoji needs Accessibility" window):
1. Click **Request Access**, then **Open System Settings**
   (System Settings → Privacy & Security → Accessibility).
2. Turn on **Macmoji** (use **+** to add it from `build/Build/Products/Debug/` or Xcode's
   DerivedData if it is not listed).
3. Setup advances by itself within a second; the menu shows "Active" once it's running.

If it stays inactive: remove the Macmoji entry with **–**, add it again, and relaunch.
Reset it completely with `tccutil reset Accessibility com.trevorgerald.macmoji`.

## Signing (so the permission survives rebuilds)
macOS ties the Accessibility grant to the app's code signature. The default config signs
ad hoc (`-`), whose identity changes on every build, so you would have to re-grant after
each rebuild. Use an **Apple Development** certificate (a free Apple ID works):

1. Xcode → Settings → Accounts → add your Apple ID → Manage Certificates → **+** →
   Apple Development.
2. Find your Team ID: `security find-identity -v -p codesigning` shows
   `Apple Development: Name (XXXXXXXXXX)`; the Team ID is on developer.apple.com → Membership,
   or in Xcode's Signing & Capabilities team list.
3. Create `Config/Signing.local.xcconfig` (gitignored):
   ```
   CODE_SIGN_STYLE = Automatic
   CODE_SIGN_IDENTITY = Apple Development
   DEVELOPMENT_TEAM = XXXXXXXXXX
   ```
4. `xcodegen generate`, build, grant Accessibility once. Later rebuilds keep the grant.
   Check with `codesign -dv --verbose=2 build/Build/Products/Debug/Macmoji.app`.

If you switch identities, re-grant once (or `tccutil reset` as above). Developer ID signing and
notarization only matter if you distribute it to others.

## Launch at login
Uses `SMAppService.mainApp` (no helper app). The toggle (setup and Settings) always shows the
live system status, since you can also change it in System Settings → General → Login Items.
For it to work reliably, **copy the built app to `/Applications`** (or `~/Applications`) and
enable it from there; registering a copy that lives in Xcode's DerivedData or `build/` makes
the login item point at that transient path. A stable signature (see Signing) also helps. If
the toggle shows "Waiting for approval", use *Open Login Items Settings…* and allow Macmoji.

## Settings
Menu bar → Settings…: enable/disable, default skin tone, launch at login, the per-app blocklist (bundle IDs;
Slack and Discord by default) and "paste mode" apps (Terminal and iTerm2 by default), where the
emoji is inserted by a clipboard paste that saves and restores your clipboard. Usage counts for
ranking are stored in `~/Library/Application Support/macmoji/usage.json`.

## Packaging (DMG)
```sh
brew install xcodegen create-dmg
scripts/make-dmg.sh                       # builds Release, writes dist/Macmoji-<version>.dmg
scripts/make-dmg.sh path/to/Macmoji.app   # or package an existing build
```
The DMG window is 660×400 with no toolbar, the app icon on the left, an Applications alias on
the right and `packaging/dmg-background.png` (+ `@2x`, merged into a Retina TIFF) behind them.
Without `create-dmg` it falls back to `hdiutil` + Finder AppleScript. The version comes from the
built app's `CFBundleShortVersionString` (i.e. `MARKETING_VERSION` in `project.yml`).

Signing and notarization are opt-in through environment variables:
- `DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)"` signs the app with the
  hardened runtime and a timestamp, and signs the DMG. (Needs a paid Apple Developer account;
  an Apple Development certificate is fine for your own Mac but can't be notarized.)
- `NOTARY_PROFILE=<profile>` (created once with `xcrun notarytool store-credentials <profile>
  --apple-id … --team-id … --password <app-specific password>`) submits the DMG with
  `notarytool submit --wait`, then staples it.

Without them you get an ad-hoc-signed DMG; other Macs will show a Gatekeeper warning.
The hardened runtime needs no extra entitlements for this app: event taps, posting events and
the AX API are governed by the user's Accessibility (TCC) grant, not by hardened-runtime
entitlements. Note that the grant is tied to the signature, so switching from a development
build to the Developer ID build means granting Accessibility once more.

The `Release DMG` workflow (`.github/workflows/release-dmg.yml`) runs on `v*` tags or manually
and uploads the DMG as an artifact; signing secrets are optional (see the workflow file).

Icon and background art are generated by `python3 packaging/make-art.py` (Pillow);
`packaging/dmg-preview.png` shows the intended window.

## Regenerating emoji data
```sh
cd scripts && npm install && node gen-emoji.mjs
```
Pinned to `emojibase-data` 18.0.0 in `scripts/package.json`.

## How it works
- A single blocking `CGEventTap` (session, keyDown and mouse-down) feeds typed characters to
  `TriggerStateMachine` (MacmojiCore). It never swallows `:` or letters; while the picker is open
  it swallows ↑ ↓ Enter Tab Esc. The tap re-enables itself when macOS disables it.
- Trigger rules: `:` counts only at the start of text or after whitespace, `(` or `[`; the picker
  opens after 2+ chars of `[a-z0-9_+-]`; space, `/` or a digit right after `:` cancel.
- Ranking: exact name → prefix → substring → fuzzy subsequence → keyword; frecency boost within
  each tier.
- The picker is a non-activating `NSPanel` hosting SwiftUI, placed via
  `kAXBoundsForRangeParameterizedAttribute`, falling back to the focused element's frame and
  then the mouse. Electron apps get `AXManualAccessibility = true`.
- Insertion: synthesized Backspaces, then `CGEvent.keyboardSetUnicodeString`, or a
  clipboard paste in paste-mode apps. Synthesized events are tagged so the tap ignores them.

## Credits
Emoji data from emojibase-data (MIT, © Miles Johnson). Shortcodes from emojibase's iamcal and
GitHub presets.
