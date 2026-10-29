# Testing macmoji

## Automated (CI and local)
- `cd MacmojiCore && swift test` — trigger state machine table tests, onboarding step sequencing and launch decision, search ranking tiers,
  frecency boost and decay, capped usage persistence/clearing, bundled emoji JSON integrity. Runs
  on macOS and Linux.
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
- [ ] Ranking: `:fire` → 🔥 first; `:+1` → 👍; after choosing 👎 several times for `:thu`, it rises above 👍 but not above an exact match.
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
