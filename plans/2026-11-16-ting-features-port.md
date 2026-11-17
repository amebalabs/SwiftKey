# Port Ting's features into SwiftKey

Bring everything Ting (`bobuk-io/ting`, 0BSD, local checkout
`~/Developer/tries/2026-11-16-ting`) offers into SwiftKey, while keeping
SwiftKey's strengths: overlay styles, GUI config editor, snippets, SF Symbols,
sticky/batch/dynamic items and deep links.

## Decisions

| Area | Decision |
|---|---|
| Approach | Copy Ting's AppKit-free code into a local SwiftPM package `Packages/SwiftKeyCore` (targets `SwiftKeyCore`, `SwiftKeyRuntime`, executable `swiftkey-micro`). Rewrite AppKit layers to fit SwiftKey's DI. No dependency on the Ting repo. |
| Baseline | Finish and commit the uncommitted refactor (`Core/Config/`, `Core/Protocols/`, `WindowManager`, …) before the port. |
| Model | `MenuItem` stays the app model and stays on Yams. An adapter maps it to the core tree. The core never imports Yams. |
| Keys | Keep SwiftKey's case-sensitive single-character keys; add `space`, `return`, `f1`…`f20`. Translate through the current ASCII-capable layout (Ting `KeyTranslator`) instead of the `"en"` layout; show local-layout hints. |
| Hotkeys | Ting's Carbon `HotkeyService` for the main key, the launcha key and per-item hotkeys. Any non-modifier key, alone or with modifiers. Remove the `KeyboardShortcuts` dependency; migrate the stored toggle key. |
| Hold mode | Kept. Double tap opens launcha except in hold mode. |
| Navigation | Extend `LeaderMachine` with sticky, batch, dynamic and open-at-path effects; `KeyboardManager.handleKey` becomes a thin effect applier. (Approved rework of existing code.) |
| Fast typing | One "Show menu after" delay, default 0.25 s, 0 = at once, for panel, notch HUD and corner toast. Menu bar style unaffected. |
| Code safety | Approve by SHA-256 of exact content for `shell://`, `dynamic://`, `micro://`. Store outside the config. Editor-typed commands are approved on save; snippet imports and outside edits are not. Items produced by an approved `dynamic://` script need no further approval. Remove the blocklist; keep the unbalanced-quotes check as a warning. |
| Deep links | `swiftkey://open?path=` runs `launch://`, `open://`, `shortcut://` as today; for `shell://`, `dynamic://`, `micro://` it only navigates and selects the item. |
| launcha | Apps, SwiftKey menu items (with breadcrumbs, icons; groups open the overlay at that path; batch groups run as batch; `hidden` items excluded; `dynamic://` contents not indexed), micro-apps, Spotlight files as fallback, calculator first. 7-day usage ranking. SwiftKey's visual style. |
| Micro-apps | Full scope. Separate files next to the chosen config: `micro/*.yaml`, `micro/libs/*.yaml`, `micro-errors.log`. Exact Ting format and names: `format: ting.microapp/2`, `$TING_*` variables. Bound with `action: micro://<id>`. |
| Task runner | `mise` (project convention). |
| Test override | `SWIFTKEY_CONFIG=/tmp/x.yaml` puts config, `micro/`, approvals, values and launcha files next to that file. Tests never touch the user's files. |
| AI/HTTP tests | Real on-device model through `fm serve` (OpenAI-compatible, `model: system`). One server per test process on a free port, health-checked. Missing `fm` or model fails the suite with an instruction; nothing is skipped. No extra Anthropic tests (only the live `fm` test is added). |
| License | Ting code is 0BSD: no attribution required; credit Ting in `THIRD_PARTY_NOTICES.md` as a courtesy. Do not copy Ting's MIT-licensed `package_app.sh` / `release.sh`. |

## Source map (Ting → SwiftKey)

| Ting | SwiftKey |
|---|---|
| `Sources/TingCore/Keys.swift`, `Leader.swift`, `Bindings.swift` | `Packages/SwiftKeyCore/Sources/SwiftKeyCore/` |
| `TingCore/Launcha.swift`, `Calculator.swift` | same |
| `TingCore/MicroApp*.swift`, `AgentPrompt.swift` | same |
| `Sources/TingRuntime/*` | `Packages/SwiftKeyCore/Sources/SwiftKeyRuntime/` |
| `Sources/TingMicroCLI/Main.swift` | `Packages/SwiftKeyCore/Sources/swiftkey-micro/` |
| `Tests/TingCoreTests/*` | `Packages/SwiftKeyCore/Tests/SwiftKeyCoreTests/` |
| `Tests/TingServiceTests/*` (runtime parts) | `Packages/SwiftKeyCore/Tests/SwiftKeyRuntimeTests/` |
| `Ting/Services/HotkeyService.swift`, `Ting/Input/*`, `Ting/Model/HotkeyRecordingGate.swift`, `Ting/Setup/LeaderField.swift` | `SwiftKey/Core/Input/` |
| `Ting/Services/MicroAppApprovalStore.swift` (generalized) | `SwiftKey/Core/Approvals/` |
| `Ting/Launcha/*`, `Ting/Services/Launcha*.swift` | `SwiftKey/Launcha/` |
| `Ting/Micro/*`, `Ting/Services/MicroApp*.swift`, `Ting/Setup/AccessibilityWindow.swift` | `SwiftKey/Micro/` |
| `docs/CONFIGURING.md`, `docs/micro-apps/FORMAT.md` + `examples/` | `SwiftKey/Resources/` (paths and names adapted; format names unchanged) |

## Validation commands

```sh
swift test --package-path Packages/SwiftKeyCore
xcodebuild -scheme SwiftKey -configuration Debug build
xcodebuild -scheme SwiftKey test
```

Every phase ends with all three passing, with no warnings in the test output.
Add `test` and `test-core` tasks to `mise.toml` next to the existing `build` task.

---

## Phase 0: Baseline

- [x] Review the uncommitted refactor (`git status`), finish what is missing, get `xcodebuild build` and `test` green
- [x] Commit it in focused commits
- [x] Branch `feature/ting-port` from that commit

## Phase 1: Core package, keys, small wins

- [x] Create `Packages/SwiftKeyCore` (swift-tools-version matching the local toolchain; macOS 15) with `SwiftKeyCore`, `SwiftKeyRuntime`, `swiftkey-micro`, test targets; link `SwiftKeyCore` into the Xcode app target
- [x] Copy `Keys.swift`, `Leader.swift`, `Bindings.swift` and their tests; rename identifiers from Ting/`io.bobuk` to SwiftKey/`com.ameba`; tests green
- [x] `MenuItemTree` adapter: `[MenuItem]` → core tree (key, title, action kind, sticky, batch, hidden, dynamic); tests
- [x] Extend `KeyName` / sequence keys: SwiftKey case-sensitive characters plus `space`, `return`, `f1`…`f20`; tests that every existing README example config still parses and resolves
- [x] Replace `englishCharactersForKeyEvent` with `KeyTranslator` (current ASCII-capable layout); local-layout hints in the panel and toast item views (the HUD and menu bar styles list no items)
- [x] `⌫` goes back one level in every overlay style
- [x] `launch://` accepts a bundle id (`launch://com.apple.Safari`) as well as a path; running app comes to the front; validator updated; tests
- [x] `SWIFTKEY_CONFIG` override for config and every SwiftKey data file; tests for path resolution

## Phase 2: Hotkeys, navigation, fast typing

- [x] Port `HotkeyService` with slots `.main`, `.launcha`, `.item(UUID)`; status reporting per slot (in use by another app, duplicate, invalid)
- [x] Per-item `hotkey:` strings parsed with `Hotkey(string:)`; `ConfigValidator` uses it; conflicts surface in `ValidationIssuesView`
- [x] Migrate the stored `KeyboardShortcuts_toggleApp` value (verify its exact UserDefaults format in the library source first) to the new setting; test with a real UserDefaults suite
- [x] Port `LeaderField` and `HotkeyRecordingGate`; replace `KeyboardShortcuts.Recorder` in onboarding, General settings and the property inspector; global hotkeys pause while recording
- [x] Remove the `KeyboardShortcuts` package
- [x] Extend `LeaderMachine` with effects for sticky, ⌥-inverted sticky, batch, ⌥ batch, dynamic loading and open-at-path; tests for each
- [x] Reduce `KeyboardManager.handleKey` to applying `LeaderMachine` effects; trace every caller (overlay, HUD, toast, faceless menu, item hotkeys, deep links) and verify each path
- [x] Hold mode on Carbon release (double tap → launcha moved to Phase 4, where launcha exists)
- [x] "Show menu after" setting; panel, HUD and toast become key at alpha 0 and reveal after the delay; HUD animation starts at reveal; fast sequences never show a window

## Phase 3: Approvals and deep links

- [ ] `Approvals` in `SwiftKeyCore`: kinds `shell`, `dynamic`, `micro`; SHA-256 of exact content; micro hash includes used libraries; encode/decode; tests
- [ ] `ApprovalStore` file layer in `Application Support/SwiftKey/approvals.json` (or next to `SWIFTKEY_CONFIG`); missing or unreadable file approves nothing; tests with temp folders
- [ ] Approval sheet: exact command, menu path, source (config / snippet name / outside edit); Approve and run, Cancel
- [ ] Gate every code-running path: key press, item hotkey, batch (one sheet for all unapproved), launcha, deep link
- [ ] Editor save approves commands typed in the property inspector; snippet import and file-watcher reloads do not
- [ ] Items produced by an approved `dynamic://` script run without further approval
- [ ] Remove the blocklist from `validateShellCommand`; keep unbalanced quotes as a warning
- [ ] Deep links: navigate-and-select for `shell://`, `dynamic://`, `micro://`; unchanged for the rest; tests
- [ ] SECURITY.md: describe the approval model and deep-link rule

## Phase 4: launcha and calculator

- [ ] Copy `Launcha.swift` (NameMatcher, KeyboardLayoutSwap, LaunchHistory, LaunchaSearch, LeaderDoubleTap) and `Calculator.swift` with tests
- [ ] `LaunchaCandidate.from([MenuItem])`: leaves with actions, groups, batch groups; breadcrumbs; excludes `hidden`; `dynamic://` item listed but not expanded; tests
- [ ] App index (`/Applications`, `/System/Applications`, `~/Applications`), refresh at most once a minute; Spotlight files fallback with Desktop/Documents/Downloads consent
- [ ] History and consent stores in `Application Support/SwiftKey/`; tests
- [ ] `LaunchaPanel` with native search field, in SwiftKey's style; ↑ ↓, Return, ⌘Return, Esc; closes on outside click and Space change
- [ ] Choosing a menu item uses the same run path as a key press (approvals, notify); a group opens the overlay at that path
- [ ] Open via double tap, launcha hotkey, menu bar menu, `swiftkey://launcha`
- [ ] Port `LeaderDoubleTap` for the main key, enabled only outside hold mode; tests
- [ ] Settings: launcha hotkey, double-tap window, calculator on/off, folder consent

## Phase 5: Micro-apps

- [ ] Copy `MicroApp*.swift`, `MicroAppYAML.swift` (strict YAML subset), libraries, templates, flow, form, output, context models with tests
- [ ] Copy `TingRuntime` (runner, ChildProcess, services incl. keychain, CLI) as `SwiftKeyRuntime`; keep `format: ting.microapp/2` and `$TING_*` names
- [ ] Micro-app folder next to the chosen config; extend `ConfigWatcher` to `micro/` and `micro/libs/`; errors to `micro-errors.log`; broken files never block others
- [ ] `micro://<id>` action in `MenuItem` handling and `ConfigValidator` (unknown id, broken file)
- [ ] Port `MicroAppFlowController`, form, flow and output views in SwiftKey's style; overlay closes on start; `notify: true` on finish; batch runs micro-apps in sequence
- [ ] Remembered values in `Application Support/SwiftKey/micro-values.json`
- [ ] Port `MicroAppContextReader`, `MicroAppKeyboard`, `AccessibilityWindow`; add `NSAppleEventsUsageDescription`; Accessibility state in Settings › Advanced
- [ ] `swiftkey-micro` built from the package, copied into `Contents/MacOS/`, signed explicitly in `release.yml` before notarization
- [ ] Integration tests: runner with real processes in temp folders; all shipped examples through `swiftkey-micro run`
- [ ] `fm serve` test fixture (free port, `/health` wait, teardown, clear failure if `fm` or the model is unavailable); AI step full and streamed answers, `max_tokens` cut; HTTP step GET/POST/404 against the same server

## Phase 6: Editor, docs, end-to-end

- [ ] Property inspector: Micro-app action type with id picker (status of each file) and Reveal file
- [ ] `CONFIGURING.md` (SwiftKey YAML + micro-apps) and `FORMAT.md` with examples in `Resources/`; "Copy prompt for agent" in Settings (port `AgentPrompt`)
- [ ] XCUITest end-to-end with `SWIFTKEY_CONFIG`: menu sequence, fast typing, back, launcha search and open, approval sheet, a micro-app with params and panel output
- [ ] README: new features, hotkeys, launcha, micro-apps, approvals, deep-link rule
- [ ] CHANGELOG entry; `THIRD_PARTY_NOTICES.md` credit to Ting
