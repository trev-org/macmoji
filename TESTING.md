# Testing macmoji

## Automated (CI and local)
- `cd MacmojiCore && swift test` — trigger state machine table tests, onboarding step sequencing and launch decision, search ranking tiers,
  frecency, picker-command matching, modifier-chord detection, tool-registry filtering, clipboard
  classification/privacy/search/dedup/pruning, index/blob persistence, and bundled emoji JSON
  integrity. Runs on macOS and Linux with a Swift 6 toolchain (the targets use Swift 5 language mode).
- CI (`.github/workflows/ci.yml`, macos-15 runner): `xcodegen generate`, `xcodebuild build`
  (unsigned), `swift test`, and a check that `emoji.json` matches a fresh regeneration.

CI cannot grant Accessibility to a custom app, so everything below is manual.

## Manual checklist (run on the bundled, signed app; not `swift run`)
Run from Xcode (Debug logs the caret source per app in Console: filter on `macmoji`).

### DMG
- [ ] `scripts/make-dmg.sh` finishes and writes `dist/Macmoji-0.1.0.dmg`; without signing env vars it prints the Gatekeeper note.
- [ ] Opening the DMG shows a 660×400 window, no toolbar/status bar, background with arrow and "Drag to Applications", Macmoji icon left and Applications alias right, both on the arrow line; sharp on a Retina display.
- [ ] Volume icon in Finder sidebar/desktop is the macmoji icon; app icon shows in Finder, Dock-less app switcher and Applications.
- [ ] Dragging to Applications copies it; launching from /Applications shows setup.
- [ ] Fallback path: with create-dmg uninstalled the layout is the same.
- [ ] With `DEVELOPER_ID_APPLICATION` + `NOTARY_PROFILE`: `spctl -a -vv /Applications/Macmoji.app` says "accepted, source=Notarized Developer ID"; `codesign -dv` shows `flags=0x10000(runtime)`; event tap + insertion still work with the hardened runtime.
- [ ] On a second Mac, the unsigned DMG shows the Gatekeeper warning (expected) and the notarized one opens cleanly.
- [ ] Release DMG workflow (tag or manual run) uploads a `Macmoji-dmg` artifact.

### First-run onboarding
Reset first: `defaults delete com.trevorgerald.macmoji` and
`tccutil reset Accessibility com.trevorgerald.macmoji`.
- [ ] First launch: the "Set up macmoji" window appears centered, frontmost and focused; menu shows "Finish setup to start".
- [ ] Before finishing, typing `:thu` anywhere does nothing (no tap; no Accessibility prompt window besides setup).
- [ ] Before finishing, copying text does not add it to clipboard history.
- [ ] Step 1: six 👋 tones shown; clicking one highlights it and "Selected: …" updates; Back is hidden; Next works.
- [ ] Step 2: Back returns to step 1 with the selection kept. Toggle on → status "On" (or "Waiting for approval" + Open Login Items Settings… button that opens General → Login Items). Toggle off → "Off". Errors show in red.
- [ ] Step 3: Next disabled until granted. Request Access / Open System Settings work. Granting it moves to step 4 within ~1 s and brings the window back to the front.
- [ ] Step 3 when already granted: shows "Access granted" and Next is enabled.
- [ ] Step 4: "Start using macmoji" closes the window; `:thu` now works; Settings shows the chosen skin tone.
- [ ] Close the window at step 2 (or Quit from the menu): next launch shows setup again from step 1.
- [ ] After finishing: relaunch goes straight to running, no setup window.
- [ ] Menu → "Run setup again…" reopens setup while macmoji keeps working; finishing again changes nothing else.
- [ ] Finish setup, then revoke Accessibility and relaunch: the separate "macmoji needs Accessibility" prompt appears (not setup).

### Launch at login (test with the app copied to /Applications, signed as in README)
- [ ] Settings → Launch at login toggle reflects the real state (compare System Settings → General → Login Items).
- [ ] Turn it off in System Settings, reactivate macmoji / reopen Settings: toggle shows Off.
- [ ] Toggle on, log out and back in: macmoji starts (smiley in menu bar), no setup window.
- [ ] Toggle off, log out and in: it does not start.
- [ ] Running from DerivedData/`build/`: the "move to /Applications" tip shows; note what status register() reports.
- [ ] Record whether macOS showed a "Background Items Added" notification or required approval.

### Tools launcher
- [ ] On a fresh install, quickly press and release ⌥⌘ together: Tools opens. Hold for at least
  0.5 seconds: nothing opens. Press a non-modifier key or move/click/scroll the mouse while holding
  ⌥⌘: nothing opens afterward and the app's normal ⌥⌘+key shortcut still works.
- [ ] Settings → Tools launcher switches among ⌥⌘, ⌃⌥, ⇧⌘ and ⌃⌘ modifier chords. Each configured
  chord works and the old one stops. Set the shortcut to Off and confirm no chord opens Tools.
- [ ] Select Keyboard shortcut, click its recorder and press a modified letter. The shortcut is
  displayed in Menu → **Tools…**, works globally through Carbon, and reports a conflict if already
  registered by another app.
- [ ] Tools opens near the mouse with Emoji Picker and Clipboard History. Search by tool name or
  keyword, navigate with ↑/↓, open with Enter/double-click, and close with Esc.
- [ ] Open Tools from a text field, then Emoji Picker. Empty search shows frequently used emoji;
  text search uses existing frecency order. Enter restores the original app and focused field,
  inserts the chosen skin-tone-aware emoji, and restores the prior clipboard.
- [ ] Open Clipboard History through Tools and verify its Enter action pastes into the field that
  was focused before Tools opened. Repeat with the target app on another Space.

### Clipboard history
- [ ] Type `:cl`, `:clip`, `:hist`, `:clipboard` and `:paste`: the visually distinct
  **Clipboard History** command appears. Prefix/keyword-prefix matches lead emoji; a weak fuzzy
  command match follows emoji. Emoji ranking remains unchanged.
- [ ] Select the command with Enter, Tab and a mouse click: `:query` is deleted before the history
  panel opens. `:clipboard:` deletes both colons and opens the panel; unrelated closing-colon emoji
  replacement still works.
- [ ] Copy plain text, an https URL, one and multiple Finder files, PNG/TIFF images, and hex colors
  (`#abc`, `#112233`, `#11223380`). Each appears with the correct type, source app and timestamp;
  image previews stay responsive and blobs exist under
  `~/Library/Application Support/Macmoji/clipboard-blobs/`.
- [ ] A large image remains responsive while its thumbnail is prepared off-main; images over
  50 MB are skipped.
- [ ] Copy the same item twice with another item between: it moves to the top without duplicating.
- [ ] Search by text, URL, file name, source app and a fuzzy subsequence. All/Text/Images/Links/Files
  filters show only the requested types.
- [ ] Pin with ⌘P: pinned items form the top section. ⌘Backspace deletes the selected item. Clear
  Clipboard History asks for confirmation, deletes unpinned entries and preserves pinned entries.
- [ ] Set each retention option and relaunch. Expired unpinned entries are removed; pinned entries
  remain. Creating more than the configured/core-tested cap does not remove pinned entries.
- [ ] Pause from the menu, copy several values, and confirm none are recorded; resume and confirm
  capture continues. Disable the feature in Settings and confirm monitoring and the inline command
  stop; Tools remains available but refuses the disabled Clipboard History tool.
- [ ] Copy from 1Password, Bitwarden, Keychain Access, LastPass and Dashlane when installed: no
  entry is recorded, including when switching apps immediately after copying. Add TextEdit to the
  excluded bundle-ID list and verify it is skipped, then remove it. Confirm concealed/transient
  password-manager clipboard items never appear.
- [ ] In the panel, ↑/↓ navigate, Enter restores the original app and pastes at the original
  location, ⌘Enter copies without pasting, and Esc closes/restores focus. Test text, links, files
  and images, including across Spaces; selection stays scrolled into view. If the original app
  quits or cannot activate, the item is copied but is not pasted elsewhere. Clipboard writes
  performed by the panel do not create duplicate history entries.
- [ ] Quit immediately after copying, relaunch and verify the item persisted. The JSON index is
  versioned and all data remains local under Application Support/Macmoji.

### Permissions and lifecycle
- [ ] After setup, with the grant revoked: "macmoji needs Accessibility" window appears; menu shows "Needs Accessibility permission" and a "Grant Accessibility…" item.
- [ ] Granting it there closes the window within ~1 s and the menu shows "Active".
- [ ] Revoke the grant while running: within ~3 s the tap stops, typing in other apps is unaffected (no stuck keyboard). Re-grant: it resumes without relaunch.
- [ ] Rebuild with an Apple Development identity: the grant survives. (With ad-hoc signing it is expected to be lost.)
- [ ] Heavy load (e.g. a breakpoint/long hang is NOT expected): after the system disables the tap (`tapDisabledByTimeout`), it is re-enabled (log line "event tap was disabled by macOS").
- [ ] Is Input Monitoring also requested? Record whether macOS asks for it (plan item marked UNVERIFIED).

### Trigger rules (in TextEdit)
- [ ] `:thu` opens the picker after `th`; `:t` alone does not.
- [ ] `time: 10:30`, `10:30`, `https://example.com`, `a:bc`, `key:value`, `::smile`, `:100` never open it.
- [ ] `(:smile` and `[:smile` open it.
- [ ] Space, `/`, uppercase letters, or punctuation close it; text is left as typed.
- [ ] Backspace shrinks the query; deleting back to 1 char hides it; deleting the `:` stops tracking.
- [ ] Clicking elsewhere, Cmd/Ctrl shortcuts, left/right arrows, or switching apps close it.

### Picker
- [ ] Appears just below the caret (above it near the bottom of the screen), never steals focus (the target window's title bar stays active, the caret keeps blinking).
- [ ] ↑/↓ move the selection and do NOT move the caret in the document.
- [ ] Enter and Tab insert the selected emoji and are not passed to the app (no newline / tab).
- [ ] Esc closes the picker, leaves `:query` text, and is not passed to the app (e.g. does not exit full screen / close a sheet).
- [ ] Clicking a row inserts it.
- [ ] Ranking: with no history, `:eye` puts exact 👁 before prefix 👀. After choosing 👀, `:eye`
  puts 👀 first; typing the exact closing form `:eye:` still auto-replaces with 👁.
- [ ] Quit and relaunch: the usage-based order is retained. Menu → **Clear Emoji History** resets
  it; quit and relaunch again to confirm the clear persisted.
- [ ] Multi-monitor: picker appears on the screen with the caret, including a screen above/left of the primary.

### Insertion
- [ ] `:thu` → Enter → `👍` with no leftover `:thu` and nothing else removed.
- [ ] `:fire:` auto-replaces with 🔥.
- [ ] Skin tone setting = Medium: `:+1` inserts 👍🏽; `:fire` stays 🔥.
- [ ] ZWJ sequences (`:man-woman-girl-boy`, `:rainbow-flag`) arrive intact.
- [ ] Paste mode (Terminal, iTerm2 by default): emoji is pasted and the previous clipboard (text and an image) is restored afterwards.
- [ ] Typing fast immediately after inserting does not reorder characters.

### Where it must stay off
- [ ] Slack and Discord: nothing happens (their own `:` picker works normally). Removing Slack from the blocklist enables it there.
- [ ] Password fields (Safari login, System Settings): never opens, nothing inserted.
- [ ] Terminal with Secure Keyboard Entry on: never opens.
- [ ] "Enabled" toggle off in the menu: never opens.

### App matrix (note caret source: caret / elementFrame / mouse)
| App | Opens | Caret placement | Insert OK | Notes |
|---|---|---|---|---|
| TextEdit | | | | |
| Notes | | | | |
| Mail | | | | |
| Safari (textarea, contenteditable) | | | | |
| Chrome | | | | AXEnhancedUserInterface is NOT set in M1 |
| VS Code / Cursor (Electron, Monaco) | | | | AXManualAccessibility set |
| Notion | | | | has its own `:` picker |
| Terminal / iTerm2 | | | | paste mode |
| Non-US layout (e.g. German, where `:` is Shift+.) | | | | |
| IME (Japanese/Chinese composition) | | | | composition not detected in M1 |
