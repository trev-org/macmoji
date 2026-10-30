# Testing rev

## Automated (CI and local)
- `cd RevCore && swift test` — trigger state machine table tests, onboarding step sequencing and launch decision, search ranking tiers,
  frecency, picker-command matching, modifier-chord detection, tool-registry filtering, launcher
  back-navigation policy, clipboard classification/privacy/search/dedup/pruning, index/blob
  persistence, snippet keyword matching/word boundaries/placeholders/search/import/persistence,
  legacy data/defaults migration, and bundled emoji JSON integrity. Runs on macOS and Linux with
  a Swift 6 toolchain (the targets use Swift 5 language mode).
- CI (`.github/workflows/ci.yml`, macos-15 runner): `xcodegen generate`, `xcodebuild build`
  (unsigned), `swift test`, and a check that `emoji.json` matches a fresh regeneration.

CI cannot grant Accessibility to a custom app, so everything below is manual.

## Manual checklist (run on the bundled, signed app; not `swift run`)
Run from Xcode (Debug logs the caret source per app in Console: filter on `rev`).

### DMG
- [ ] `scripts/make-dmg.sh` finishes and writes `dist/Rev-0.1.0.dmg`; without signing env vars it prints the Gatekeeper note.
- [ ] Opening the DMG shows a 660×400 window, no toolbar/status bar, background with arrow and "Drag to Applications", Rev icon left and Applications alias right, both on the arrow line; sharp on a Retina display.
- [ ] Volume icon in Finder sidebar/desktop is the rev icon; app icon shows in Finder, Dock-less app switcher and Applications.
- [ ] Dragging to Applications copies it; launching from /Applications shows setup.
- [ ] Fallback path: with create-dmg uninstalled the layout is the same.
- [ ] With `DEVELOPER_ID_APPLICATION` + `NOTARY_PROFILE`: `spctl -a -vv /Applications/Rev.app` says "accepted, source=Notarized Developer ID"; `codesign -dv` shows `flags=0x10000(runtime)`; event tap + insertion still work with the hardened runtime.
- [ ] On a second Mac, the unsigned DMG shows the Gatekeeper warning (expected) and the notarized one opens cleanly.
- [ ] Release DMG workflow (tag or manual run) uploads a `Rev-dmg` artifact.

### Upgrade migration
- [ ] Start with the old `Macmoji.app` data and defaults, including completed onboarding, a
  non-default skin tone/Tools shortcut, custom blocklists, snippets, clipboard history and an
  image blob. Make sure `~/Library/Application Support/Rev/` does not exist.
- [ ] Launch Rev: onboarding stays completed; all old settings are present; usage, snippets,
  clipboard entries and image previews load from `Application Support/Rev`.
- [ ] Confirm the old `Application Support/Macmoji` (or lowercase `macmoji`) data is still present;
  migration copies it instead of moving it.
- [ ] Change a Rev setting and data file, then relaunch. The migration does not overwrite the new
  values or re-copy deleted legacy data.
- [ ] Grant Accessibility and enable Rev under Login Items again; neither approval transfers to
  the new `com.trevorgerald.rev` bundle identifier.
- [ ] After confirming the migration, delete the old `Macmoji.app`; Rev continues to work.

### First-run onboarding
Reset first: `defaults delete com.trevorgerald.rev` and
`tccutil reset Accessibility com.trevorgerald.rev`.
- [ ] First launch: the "Set up rev" window appears centered, frontmost and focused; menu shows "Finish setup to start".
- [ ] Before finishing, typing `:thu` anywhere does nothing (no tap; no Accessibility prompt window besides setup).
- [ ] Before finishing, copying text does not add it to clipboard history.
- [ ] Step 1: six 👋 tones shown; clicking one highlights it and "Selected: …" updates; Back is hidden; Next works.
- [ ] Step 2: Back returns to step 1 with the selection kept. Toggle on → status "On" (or "Waiting for approval" + Open Login Items Settings… button that opens General → Login Items). Toggle off → "Off". Errors show in red.
- [ ] Step 3: Next disabled until granted. Request Access / Open System Settings work. Granting it moves to step 4 within ~1 s and brings the window back to the front.
- [ ] Step 3 when already granted: shows "Access granted" and Next is enabled.
- [ ] Step 4: "Start using rev" closes the window; `:thu` now works; Settings shows the chosen skin tone.
- [ ] Close the window at step 2 (or Quit from the menu): next launch shows setup again from step 1.
- [ ] After finishing: relaunch goes straight to running, no setup window.
- [ ] Menu → "Run setup again…" reopens setup while rev keeps working; finishing again changes nothing else.
- [ ] Finish setup, then revoke Accessibility and relaunch: the separate "rev needs Accessibility" prompt appears (not setup).

### Settings window
- [ ] With no Dock icon present, choose menu → **Settings…** while another app is active. The
  rev Settings window appears in front and accepts keyboard input.
- [ ] Close Settings, switch to another app, and choose **Settings…** again. The same behavior
  works repeatedly, including from a different Space.
- [ ] Click the shortcut recorder, then close Settings without pressing a key. Typing in another
  app is unaffected; reopening Settings shows the previous shortcut.

### Launch at login (test with the app copied to /Applications, signed as in README)
- [ ] Settings → Launch at login toggle reflects the real state (compare System Settings → General → Login Items).
- [ ] Turn it off in System Settings, reactivate rev / reopen Settings: toggle shows Off.
- [ ] Toggle on, log out and back in: rev starts (smiley in menu bar), no setup window.
- [ ] Toggle off, log out and in: it does not start.
- [ ] Running from DerivedData/`build/`: the "move to /Applications" tip shows; note what status register() reports.
- [ ] Record whether macOS showed a "Background Items Added" notification or required approval.

### Tools launcher
- [ ] On a fresh install, press ⌥Space: Tools opens and menu → **Tools…** displays ⌥Space.
- [ ] Upgrade once with the previous ⌥⌘ default saved: it changes to ⌥Space. Repeat with a custom
  key shortcut, a custom modifier chord, and Off saved: each remains unchanged after upgrading
  and relaunching.
- [ ] Settings → Tools launcher switches among ⌥⌘, ⌃⌥, ⇧⌘ and ⌃⌘ modifier chords. Quickly press
  and release each configured chord to open Tools. Holding it for at least 0.5 seconds, pressing a
  non-modifier key, or moving/clicking/scrolling the mouse cancels it. The old shortcut stops.
- [ ] Select Keyboard shortcut, click its recorder, and press another modified key, including
  Space. The shortcut is displayed in Menu → **Tools…**, works globally through Carbon, and
  reports a conflict if another app already registered it. Set the shortcut to Off and confirm
  neither the key shortcut nor a modifier chord opens Tools.
- [ ] Tools opens near the mouse with Emoji Picker, Clipboard History and Snippets. Search by tool
  name or keyword, navigate with ↑/↓, open with Enter/double-click, and close with Esc.
- [ ] Open each tool from Tools. With text in its search field, Backspace deletes one character
  and stays in the tool. With the search empty, Backspace returns to Tools with that tool still
  selected. Repeat after filtering the Tools list and confirm its query and selection are kept.
- [ ] Open Clipboard History and Snippets directly from the menu bar and through `:cl` / `:sn`.
  Backspace in an empty search does not open Tools; the back path exists only for launcher-opened
  tools.
- [ ] Open Tools from a text field, then Emoji Picker. Empty search shows frequently used emoji;
  text search uses existing frecency order. Enter restores the original app and focused field,
  inserts the chosen skin-tone-aware emoji, and restores the prior clipboard.
- [ ] Open Clipboard History through Tools and verify its Enter action pastes into the field that
  was focused before Tools opened. Repeat with the target app on another Space.
- [ ] Open Snippets through Tools and verify Enter inserts into the app and exact field that was
  focused before Tools opened.

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
  `~/Library/Application Support/Rev/clipboard-blobs/`.
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
  versioned and all data remains local under Application Support/Rev.

### Snippets
- [ ] Menu → **Create Snippet…** opens a focused editor. Save multi-line text with a name and
  keyword; each placeholder-menu item is inserted. Empty names/text and a keyword already used by
  another snippet show validation errors. Edit the snippet with ⌘E and verify its created date is
  preserved while its modified date changes.
- [ ] Type `:sn`, `:snippet`, `:text` and `:template`: the **Snippets** command appears without
  changing emoji ranking. Select it with Enter, Tab and a click; the typed `:query` is removed and
  the snippets panel opens. `:snippets:` opens it through exact command replacement.
- [ ] Search snippets by name, keyword, body substring and fuzzy subsequence. Frequently used
  matches rank ahead of unused matches. ↑/↓ keep the selection visible; the right side previews
  the text after placeholder expansion.
- [ ] Open the panel from TextEdit, then switch selection and press Enter: TextEdit is restored and
  the snippet is pasted at the original caret. ⌘E edits, ⌘N creates, ⌘Backspace deletes and Esc
  restores focus without inserting. If the original app quits, Rev does not paste elsewhere.
- [ ] Create keywords `;sig` and `!email`. At the beginning of a document and after whitespace,
  typing each exact keyword expands it; a partial keyword does not. With word-boundary mode on,
  `word;sig` does not expand. Turn the boundary requirement off and confirm it does.
- [ ] Start an emoji shortcode and a snippet keyword with punctuation (including a `:` keyword):
  exact snippet expansion wins only when its full keyword is typed, while normal `:emoji` picker
  and closing-colon replacement behavior remains unchanged.
- [ ] Move focus, click, press a navigation key and use Backspace partway through a keyword; stale
  buffered characters never trigger an expansion in the new location.
- [ ] Disable keyword expansion: direct keywords remain untouched while **Snippets…** search and
  insertion still work. Add TextEdit to the snippet exclusion list and confirm expansion is off
  only there; remove it and confirm expansion resumes.
- [ ] In a password field and with Secure Keyboard Entry enabled, snippet keywords never expand.
  The general app blocklist also disables both emoji and snippet event-tap behavior.
- [ ] Verify `{clipboard}`, `{date}`, `{time}`, `{datetime}`, `{day}`,
  `{date format="MMM d, yyyy" offset="+2d"}` and `{cursor}`. Multi-line text is preserved and the
  caret lands at `{cursor}` after insertion.
- [ ] Before expansion, copy both text and an image. The snippet is pasted, clipboard history does
  not record the temporary value, and the original clipboard item and all of its pasteboard types
  are restored shortly afterward.
- [ ] Export snippets, delete them, then import the Rev JSON and verify metadata/use counts
  survive. Import a Raycast-style array of `{name, text, keyword}` and verify valid entries are
  added while duplicate keywords are reported as skipped.
- [ ] Quit immediately after creating or using a snippet, relaunch, and verify
  `~/Library/Application Support/Rev/snippets.json` is versioned and contains the latest use
  count and timestamps.

### Permissions and lifecycle
- [ ] After setup, with the grant revoked: "rev needs Accessibility" window appears; menu shows "Needs Accessibility permission" and a "Grant Accessibility…" item.
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
- [ ] "Emoji Autocomplete" toggle off in the menu: emoji picker/replacement stays off while
  snippet inline commands and enabled keyword expansion continue to work.

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
