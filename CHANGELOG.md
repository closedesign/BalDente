# Changelog

## Road to 1.0
BalDente stays on 0.x until: it is notarized, it has been tested on at least three Mac models and two macOS versions, it has had a week of daily use
without a charging bug, and the helper installs, updates and uninstalls cleanly on a fresh account.

## 0.6 (unreleased)
- **Update the helper after installing this version** (General → Charging helper → Update). It fixes daemon bugs listed below.
- First-run tutorial: what a charge limit is and your default limits, then a guided tour of the real window that dims everything else and points at each control in turn (zones, Top Up, Ready by, Heat Protection, the menu bar icon, Recent changes). The highlighted control stays clickable. Replay it from General, About or the Help menu.
- The defaults are shown up front, and a new install can choose "80% everywhere" instead of the zone defaults.
- While charging is held below 100%, Overview and the menu bar panel say why, with prominent Top Up and Ready by buttons one click away. Dismiss it, or it retires after a few uses.
- Habit suggestions: BalDente learns when you usually unplug and suggests a Ready by plan. Nothing changes until you tap Accept. Turn it off or clear what it learned in General.
- Accept or snooze a habit suggestion straight from its notification.
- Zone suggestions: a Wi-Fi network you join regularly that no zone has is offered for a zone (or a new one). Suggest only.
- The compact layout now shows the holding hint, suggestions and Recent changes too.
- A notification for every limit change, always with the reason, with a switch per kind in General.
- Recent changes on Overview: what changed, when and why.
- Drag the limit and resume markers on the Overview ring to change the active zone's limits. The band between them is shaded.
- This What's New sheet after each update.
- Fix (helper): a client that gave up waiting could crash the helper (SIGPIPE).
- Fix (helper): heat protection could report "cooling down" during a Ready by top-up, and lost track of the temperature while a task ran.
- Fix (helper): turning Ready by off now also ends a top-up it had started.
- Fix (helper): zone labels are cleaned the same way by app and helper (empty names, spaces, control characters), so Ready by "only in zone" matches reliably and the app no longer resends the limit on every refresh for an unnamed zone.
- Fix (helper): only the first line of a command is read, out-of-range heat limits are refused instead of ignored, and a failing socket no longer spins a CPU core.
- Fix: two zones with the same name (or a zone named "Default" or "Top Up") no longer both light up as active; names are made unique when the zone editor closes.
- Fix: battery history keeps the last reading of a duplicated day regardless of sort order, and ignores impossible values.
- Fix: a battery health reading that goes up (after calibration) resets the health-drop baseline instead of hiding a later drop.

## 0.5 (unreleased)
- Performance: the settings window no longer uses 25-50% CPU (GPU-animated background), the menu bar animation costs about a third of what it did,
  and network checks no longer spawn a process every few seconds.
- Fix: closing the settings window no longer quits the app and removes the menu bar icon.

## 0.4 (pre-release)
- The live preview in settings now looks like the real macOS menu bar (Apple menu, app menus, status icon with text, Control Center, clock).
- The speed setting drives the whole charging animation (0.1x to 3x); the charging bolt is larger.
- Donate buttons (Ko-fi, Buy Me a Coffee) on About, Overview and the compact layout.
- The window resizes down to about 640 x 470.
- Heat Protection: limit up to 60 °C, thermometer control with keyboard entry, default 35 °C.
- Menu bar: charging wave with adjustable speed, percentage beside the icon while charging, time remaining on by default.
- Ready by opens in one click; jumping to a setting now highlights it clearly.
- Calibration scheduling row redesigned.
