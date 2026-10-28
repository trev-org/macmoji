# Testing macmoji

## Automated (CI and local)
- `cd MacmojiCore && swift test` — trigger state machine table tests, search ranking tiers,
  frecency boost and decay, usage persistence, bundled emoji JSON integrity. Runs on macOS and Linux.
- CI (`.github/workflows/ci.yml`, macos-15 runner): `xcodegen generate`, `xcodebuild build`
  (unsigned), `swift test`, and a check that `emoji.json` matches a fresh regeneration.

CI cannot grant Accessibility to a custom app, so everything below is manual.

## Manual checklist (run on the bundled, signed app; not `swift run`)
Run from Xcode (Debug logs the caret source per app in Console: filter on `macmoji`).

### Permissions and lifecycle
- [ ] Fresh install, no grant: onboarding window appears; menu shows "Needs Accessibility permission".
- [ ] "Request Access" shows the system prompt; "Open System Settings" opens Privacy & Security → Accessibility.
- [ ] Enabling macmoji there closes the onboarding window within ~1 s and the menu shows "Active".
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
