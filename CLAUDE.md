# BalDente — agent notes

Free, open-source BattOpt/AlDente alternative for macOS: battery charge limiting via SMC, with
Wi-Fi/location "zones" that switch limits automatically. Swift Package Manager project, no Xcode
project file. Not a git repo yet — if you add one, use `.gitignore` for `.build/` and `dist/`.

## Architecture (see `PLAN.md` for the live milestone list)
- `Sources/CSMC` (C) — raw AppleSMC read/write via IOKit. Low-level, security-sensitive.
- `Sources/BalDenteCore` (Swift) — config, zones, limiter policy, Wi-Fi detection, battery info,
  the daemon↔CLI/app wire protocol (`Protocol.swift`, `Client.swift`).
- `Sources/baldented` — root `LaunchDaemon` that actually applies the charge limit; listens on a
  Unix socket. This process runs as root.
- `Sources/baldente` — CLI client that talks to the daemon over the socket.
- `Sources/BalDenteApp` — SwiftUI app + AppKit status item. `Model.swift` is the single `@MainActor` state object.
  `MainWindow.swift` is the sidebar shell (search box, ⌘F, routes `SettingsPage` → page views); pages live in
  `OverviewPage`, `ChargingPage`, `ConfigPages` (zones, appearance, general, about) and `Trio/TrioSettingsView.swift`
  (menu bar pages). `Pages.swift` holds `SettingsPage` and `SettingsIndex` (the searchable list). `HistoryPage.swift` charts the daily log, shows the 80%-health projection, and offers export/reset (parsing, per-day dedupe, summary and projection math in `BalDenteCore/History.swift`, unit-tested); `CalendarReady.swift`
  sets Ready by from EventKit (event-driven, no polling; slot math in `ReadyPlan`). `Compact.swift` is the dense alternative layout. `Tutorial.swift` has the first-run intro sheet and What's New; `GuidedTour.swift` is the spotlight tour (steps point at
  `settingAnchor`/`tourAnchor` ids; anchors use `transformAnchorPreference` so a group's anchor doesn't hide its rows'). Add a tour step by anchoring the view and adding a `TourStep`. `Trio/` also has the status item controller, renderer, panel and system monitor.
- Helper-side extras (all behind new `baldented` commands, so they need a helper update): `Tasks.swift` (`ScheduledTask` recurrence math, `TaskBook`, wire format; daemon runs due tasks in `runDueTasks`, history in `taskLog`), sleep hooks (`Hooks.swift`: C callbacks must live outside `main.swift`), `MagSafeLED` (`ACLC`), `LeaveTime` (travel time; slots always store *leave* times and `ChargeSchedule.travelMinutes` is display metadata only).
  App-side: `AutoDischarge.swift`, `AutomationURL.swift` (`baldente://`, parsed in Core, run by `Model.run`), `AutomationState.swift` (`baldente get`), `ReadyPreview.swift` (Overview "Leaving" card), `PowerFlow.swift`, `AutomationCards.swift` (Sleep, Schedule, LED cards).
- Keeping users informed (all UI-free, unit-tested in Core): `Onboarding.swift` (defaults explainer read from `Config()`/`HeatLimit`,
  the "80% everywhere" preset, the hold hint, `TutorialVersion`), `HabitPlanner.swift` (unplug history in `habits.json`, suggestion math), `NetworkHints.swift` (unknown Wi-Fi seen often → "add it to a zone?", `network-habits.json`),
  `Activity.swift` (`ChangeEvent` wording + `NotifyCategory`, the Recent changes log in `activity.json`), `WhatsNew.swift` (CHANGELOG section parser).
- `Sources/smcprobe` — standalone probe (`swift run smcprobe`) for discovering which SMC keys this
  Mac exposes and whether they're writable as a normal user. Run this first on unfamiliar hardware
  before assuming a backend works.

## Build / test
```bash
swift build                 # debug build of all targets
swift test                  # BalDenteCoreTests (pure logic only; see Gotchas for the scratch-path flag)
swift run smcprobe          # probe SMC keys on this Mac
./make_app.sh               # build release, assemble dist/BalDente.app, ad-hoc codesign
./make_app.sh --dmg         # also build dist/BalDente.dmg
./install.sh                # build, install to /Applications, launch (kills running instance first)
```
There's no Xcode project — everything goes through `swift build`/`swift test` or the shell scripts.

## Adding or changing a setting (keep search working)
1. Add the row with `SettingRow`/`SettingsGroup` (they call `.settingAnchor(title)` so search can scroll to and flash them).
2. Add a matching `SettingsIndex` entry in `Pages.swift`; its title must equal the row title (or set `anchor:`).
3. Ranking logic is `BalDenteCore/SettingsSearch.swift` and is unit-tested; keep UI-free logic in Core.

## Announcing changes
- Every limit change goes through `Model.announce(ChangeEvent)`: it always appends to Recent changes and notifies unless that category is muted.
  Add new wording to `ChangeEvent` (Core), not ad-hoc `notify` calls. Habit and zone suggestions only suggest; never apply a schedule or add a network without the user's tap.
  Habit notifications carry Accept/Not now actions (`Model` is the `UNUserNotificationCenter` delegate); they act only if the notification's
  `signature` still matches the current suggestion.
- What's New reads this version's `## <version>` section of `CHANGELOG.md` (copied into the bundle by `make_app.sh`); keep its entries as `- ` bullets.
- Bump `TutorialVersion.current` only when the tour changes enough to re-show it to people who saw the old one.

## Versioning
- The version lives in the `VERSION` file (read by `make_app.sh`; the build number is the git commit count). **Bump it after every major change**
  (a new feature, a user-visible behavior change, or a notable fix), add a matching `## <version>` heading to `CHANGELOG.md`, and say so in the commit.
- We are pre-1.0 on purpose: stay on `0.x` (bump the minor for features and big fixes, e.g. 0.5 to 0.6). Tag releases `v<version>` and publish them as GitHub
  pre-releases until the 1.0 checklist in `CHANGELOG.md` is done: notarized build, tested on at least three Mac models and two macOS versions, a week of daily use
  without a charging bug, and a clean install/update/uninstall of the helper on a fresh account.

## README upkeep (do this every time)
- **Whenever you add, change or remove a user-visible feature or setting, update `README.md` in the same change** (the "All features" list, and
  "Zones" if it touches zones), plus `CHANGELOG.md`. The README is the public sales page (github.com/closedesign/BalDente); keep claims true to the code.
- Keep the **Zones** section highlighted: zone switching by Wi-Fi or saved place is the headline feature, and it is free here whereas other
  battery limiters usually charge for it. Don't make claims about specific competitors' features that can't be verified.
- Defaults to state accurately: a fresh install ships zones **Home 50%/45%**, School 80%/75%, Travel 100%/95%, and "Everywhere else" 80%/75%
  (`Config.init` in `BalDenteCore/Zones.swift`). **Out of the box charging is limited to 50% at home**; the Home zone applies once the user adds
  their home Wi-Fi. Heat Protection defaults to 35 °C (range 30–60, `BalDenteCore/HeatLimit.swift`).
- Donate buttons (Ko-fi, Buy Me a Coffee: `SupportLinks` in `ConfigPages.swift`) appear on About, Overview and the compact layout, and in the README and
  `.github/FUNDING.yml`. Keep them in sync if the handles change (both are `closedesign`).
- Screenshots live in `docs/images/`; retake them when a page's look changes noticeably (no real Wi-Fi names, no helper-update banner).

## Performance rules (priority for this app)
- Measured costs (keep them in mind): the settings window used to burn 25-50% of a core because the aurora background was a SwiftUI `TimelineView`
  (it re-evaluated every glass card per frame). It is now Core Animation layers (`DriftingGlow` in `Theme.swift`); never animate SwiftUI state per frame
  in the window. The menu bar animation draws a cached bitmap (`TrioRenderer.bitmapImage`) at 8-16 fps, scaled by the speed setting; avoid `setShadow`
  blur and per-frame font creation in `TrioRenderer`. Network polling must not spawn processes every poll (`cachedGateway`).
- Profile with `sample <pid> 5 -file out.txt` and `ps -o cputime= -p <pid>` deltas over 30 s, with the window closed and open, and with
  `BALDENTE_TEST_CHARGING=1` for the animation. Closing the window must not quit the app (`AppDelegate`).
- No new timers or polling. Use notifications/events that already arrive; piggyback on `Model.refreshStatus` (20 s) or
  the once-a-day log. The only fast timer is the charging animation (20 fps), which stops when not charging, the display
  sleeps, or Reduce Motion is on. Only touch `NSStatusBarButton` properties when the value changed.
- Never talk to the daemon on the main thread: use `Model.cmd(_:)` / `refreshStatus()` (serial `daemonQueue`).
- Don't change `baldented` unless necessary: any change forces users to reinstall the helper (password prompt).

## Layout rules
- `SettingRow` uses `RowControlLayout` (control beside the label, or under it when the label would get under 230pt); pages of cards use `MasonryLayout` (1-3 columns).
  Rules live in Core (`RowLayoutRule`, `ColumnRule`) so they're tested. The window has no minimum size; the sidebar goes icon-only under 520pt.
- The helper banner is a `safeAreaInset` on the page ScrollView. Stacked above it, the ScrollView's square clip edge cut into the banner's rounded glass.
- Use `Color.primary` (not `.white`) for overlays so Light/Dark/System themes work.

## Gotchas
- With the CHIE backend macOS keeps reporting "AC Power" while the charger is held off, so `power.plugged` is reliable;
  older keys report "Battery Power" when held (`Model.onBattery` handles both).
- The menu bar animation only plays when macOS says *charging*; at the limit it is idle by design.
- `swift test` can fail to code-sign inside ~/Desktop (Finder xattrs). Use `swift test --scratch-path <dir outside Desktop>`.
- Launching the debug binary from a shell crashes (Bluetooth TCC); wrap it in a throwaway .app with its own bundle id and start
  it with `open -n --env BALDENTE_TEST_CHARGING=1 …` (that env var forces the charging animation).
- The heat-limit range (30–60 °C) and default (35 °C) live in `BalDenteCore/HeatLimit.swift` and are shared with `baldented`; changing them means users must update the helper.
- Zone names must be unique and not reserved ("Default", "Top Up", "Travel Mode", "manual"); use `Model.addZone()`, and the zone editor calls
  `Model.fixZoneName` on close. Tiles mark the active zone by `target.zoneID`, not by label.
- Labels sent to the helper go through `Target.wire` (Core); `baldented` applies the same function, so app and helper always agree on the label.
- A throwaway test bundle (even with `BALDENTE_DEMO=1`) reads and writes the real `~/Library/Application Support/BalDente/config.json`; back it up before UI tests that change limits.
- The Overview ring's markers are draggable (`BatteryRing.onLimitsChange`, math in `BalDenteCore/RingDrag.swift`); it commits once on release via `Model.setTargetLimits`.
- Habit unplugs are confirmed after a fresh status (`pendingUnplug`): with older SMC keys a held charger also reads as unplugged.

## Updates
- `UpdateCheck` (Core) parses GitHub releases; `UpdatesView`/`Updater.swift` (App) show it in About and do the install swap. Install only works when a release has a
  `BalDente.dmg` asset from `closedesign/BalDente` (attach `dist/BalDente.dmg` when publishing). Settings never live in the bundle, so replacing it is safe.
- Keep every persisted type decoding with `decodeIfPresent` defaults; `SettingsBackup.swift` snapshots config per version and `trackSettings` verifies after an update.

- New fields on `Status`/`LimiterState` must be optional or custom-decoded: an old helper must not make a new app think the helper is offline, and the reverse.
- Every new helper command parses fixed tokens with range checks (the socket buffer is 512 bytes); never decode JSON from the socket.
- Scheduled tasks never set the limit (zones own it and the app re-sends it every refresh). The LED key is only written once the user picks a mode (`lastLED`).
- `AppIntents` need Xcode's metadata step, which SwiftPM does not run, so Shortcuts works through `baldente://` and the CLI instead.

## Battery data
- Health % = `NominalChargeCapacity / DesignCapacity` (what System Settings shows; `FullChargeCapacity` reads ~2 points lower). Legacy keys are fallbacks only.
- `daily-log.csv` is one row per day; `HealthHistory.parse` keeps the last row of any duplicated day. `Model.resetHistory()` also clears the
  `lastLogDay`/`healthBaseline*` defaults, so use it instead of deleting the file by hand.

## Permissions
Calendar access (`NSCalendarsFullAccessUsageDescription` in `make_app.sh`) is used only for the start time of the next timed event
when "Calendar Ready by" is on. Don't widen it without updating those strings.

## Safety-critical surface — read before touching
- **`baldented` runs as root** via `SMAppService`/LaunchDaemon. Anything it does — socket
  handling, parsing client input, applying SMC writes — is privileged-process code. Treat its
  input parsing as untrusted even though the only client today is the local CLI/app.
- **SMC writes can affect charging/thermal behavior on real hardware.** Don't guess at key
  semantics or add new write paths without checking `PLAN.md`'s findings on legacy vs. firmware
  backends first. Prefer reads and `smcprobe` experiments over blind writes when exploring.
- The app requests `NSLocation*UsageDescription` for Wi-Fi/zone detection — don't widen location
  usage beyond zone switching without updating the Info.plist strings in `make_app.sh` to match.
- `make_app.sh` ad-hoc codesigns (`codesign --sign -`); that's expected for local dev, not a bug.
- Reference projects named in `PLAN.md` (`actuallymentor/battery`, `charlie0129/batt`,
  `mhaeuser/Battery-Toolkit`) are license-encumbered (GPL) or source-unavailable (BattOpt) — read
  them for ideas only, never copy code without checking the license first.

## Conventions
- Small, flat files per concern (`Backend.swift`, `BatteryInfo.swift`, `Zones.swift`, etc.) rather
  than one large module — keep new code in a similarly-scoped file instead of growing an existing
  one indefinitely.
- No external dependencies today (`Package.swift` has none) — don't add one without a clear reason;
  this is a small, auditable system-level tool.
- Tests live in `Tests/BalDenteCoreTests` and currently cover pure logic (zones, the Trio status
  icon renderer) rather than anything that touches real SMC hardware or root privileges — follow
  that pattern (keep hardware/privileged code thin and test the logic around it).

## Working with the user
- Ask a short question (AskUserQuestion) when a decision is genuinely theirs: behavior/UX choices, anything touching `baldented`/SMC, permissions. Don't ask about things the code or this file answers.
- After finishing a task, suggest 1-3 concrete feature ideas that fit the app's goals (battery longevity, zones, performance). Don't build them unasked.
- Aim for quality over minimal diffs: when you touch a feature, check the neighbouring edge cases (empty data, duplicates, first run) and add a unit test for new Core logic.

## Keeping this file useful (read at the end of every task)
- Add what a future session would otherwise have to rediscover: a gotcha that cost time, a decision and its reason, a changed workflow. One or two lines, in the section it belongs to.
- Remove what is now false, fixed, or irrelevant: a gotcha whose bug is gone, a file list entry for something renamed, a test list that drifted. Stale notes mislead more than missing ones.
- Be careful deleting: only remove an item after confirming it's wrong or obsolete (grep/read the code). If unsure, keep it and mark it "(unverified)".
- Keep it short. Don't record things the code or filenames already make obvious, or one-off task history.

## Saving tokens
- Work inline; don't spawn subagents for a codebase this small. Use `grep -n`/`sed -n` ranges instead of reading whole files, and only read files you'll edit.
- Batch related edits into one Python/Edit pass, then one `swift build`; run `swift test` once at the end.
- Don't re-read files you just edited, don't re-run passing builds, and keep command output short (`| tail`, `grep error:`).
- UI check: one scaled `app_screenshot` of the throwaway bundle, not many. Background clicks on overlay buttons can arrive as
  "raw input" and fire twice (an extra mouse-up), so a tour that skips steps under test is the tool, not the app; prefer AXPress (element_index).
- Prefer `/compact` or a fresh session between unrelated tasks.

## Model guidance for agents working in this repo
- **Sonnet 5.5 (default)** for most work here: implementing milestones from `PLAN.md`, SwiftUI
  view code in `BalDenteApp`, the CLI/daemon protocol, zone logic, tests, build script tweaks.
  This is a small, well-scoped codebase — straight-line edits don't need a heavier model.
- **Opus 5.5** when a task needs more deliberation before writing code:
  - Designing the `baldented` ↔ `baldente`/`BalDenteApp` wire protocol or socket security model
    (it's root-privileged — mistakes here are a local-privilege-escalation surface).
  - New SMC backend logic (legacy vs. firmware-limit keys) where getting it wrong risks battery
    health or thermal behavior on real hardware, not just a bug to fix later.
  - Packaging/signing/entitlements decisions (`SMAppService` registration, notarization,
    `LaunchDaemon` plist) where a wrong call is awkward for users to recover from.
  - Cross-cutting refactors that touch `CSMC` C code, `BalDenteCore`, and the daemon together.
- Either model: run `swift build` and `swift test` after non-trivial changes before reporting
  done — this is a compiled Swift project, not something you can eyeball-verify. For anything
  touching `baldented`/SMC, prefer testing on `smcprobe` output or the CLI against a locally
  running daemon over assuming the change is correct from reading the code.
