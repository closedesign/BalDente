# Changelog

## Road to 1.0
BalDente stays on 0.x until: it is notarized, it has been tested on at least three Mac models and two macOS versions, it has had a week of daily use
without a charging bug, and the helper installs, updates and uninstalls cleanly on a fresh account.

## 0.13 (pre-release)
- **Shorter menu bar panel:** it now stops at 520 points instead of filling the screen height, and Settings, Dashboard and Quit stay pinned at the bottom.
- **Obvious scrolling:** when more sections are below, the panel fades out at the bottom, shows the scroll bar and a **More** button that scrolls down for you.
- **Charge normally for a while:** a clock button next to Top Up lifts the limit for 1, 2, 4 or 24 hours, then it comes back by itself.
- **Time above 80% per zone:** Battery History shows how many hours each zone held the battery above 80% this week, and suggests lowering a zone that does it a lot (only when you tap).
- **Tour:** steps now have buttons that do the thing: allow Location, add your current Wi-Fi to Home, or open the menu bar panel. The Calendar step says when access is off, and Macs whose older charging keys report "Battery Power" while held are told that's normal.
- **Fix:** the panel no longer changes from dark to light as you scroll.
- **Fix:** with many zones the zone pins no longer push Top Up out of the panel; they fold into one menu.
- **Fix:** the tutorial's last page no longer has an invisible Skip button.

## 0.12 (pre-release)
- **Fix:** the charging wave on the menu bar ring is now a single crest that travels along the filled arc and repeats, instead of several crests that made the two sides look like separate waves.
- **Fix:** the ring keeps its normal green while charging; the wave no longer darkens it.

## 0.11 (pre-release)
- **Faster:** the live menu bar preview no longer redraws the whole settings page every frame while charging (about 40% of a core down to about 5%).
- **Fix:** deleting a zone from its editor could crash the app.
- **Fix:** notifications are now shown while the BalDente window is in front, instead of only landing in Recent changes.
- **Fix:** installing an update can no longer leave you without an app if moving the new copy into place fails; the old one is put back.
- **Fix:** Export history no longer offers to overwrite a file when there is no history to export yet.
- **Fix:** the app reads status from older helpers that lack newer fields instead of reporting the helper as offline.

## 0.10 (pre-release)
- **Text and buttons now adapt to the window:** setting rows move their control under the label when the window is narrow instead of squeezing the words into a column.
- **Update downloads show a progress bar** with percent, size and speed, plus a Cancel button.
- **The window can be any size:** no minimum. The sidebar shrinks, then turns into icons only (the magnifier or ⌘F expands it), and padding and titles scale with the width.
- **Helper setup banner:** liquid glass again. It now scrolls with the page, so the page's square clip edge no longer cuts into it, and in small windows the button sits centered below the text.
- **Wide windows use up to three columns** on Charging Tools, General, Appearance and the menu bar pages (and the page width limit is higher).
- **Helper banner stays pinned** at the top while the page scrolls under it, and when the helper isn't installed it now says so plainly and lists what won't work.
- **Light, Dark or System window theme** (Appearance → Background).
- **Overview and History use the width:** cards flow into up to three columns in wide windows.
- **"Install helper" button** on each charging card while the helper isn't running, so greyed-out controls explain themselves.
- **Menu bar quick menu:** right-click the icon to Top Up or pin a zone.
- **Settings export/import and a diagnostics report** (General → Settings file and support).
- **The window remembers its size, position and last page.**
- **Fixed:** Automatic Discharge forgot its on/off setting after a restart.
- **What's New formatting:** bold and code render properly, with aligned bullets.
- **More backgrounds:** 12 new color presets (20 in all) and four background styles: Aurora, Gradient, Spotlight and Midnight (Appearance → Background).

## 0.9 (pre-release)
- **Update the helper after installing this version** (General → Charging helper → Update). New helper features need it; the new controls stay greyed out until then.
- **Schedule:** run Top Up, Discharge, Calibration or Low Power Mode on a schedule (once, daily, weekdays, weekly, every two weeks, monthly, yearly), with "catch up if the Mac was asleep" and a task history. A limit is not a task: zones set the limit.
- **Sleep:** "Stop charging when sleeping" cuts the charger as the Mac sleeps (not below 20%), and "Stay awake until the limit" keeps the Mac awake only while it charges toward the limit.
- **Automatic Discharge:** when the limit drops below the battery with the charger in, drain to it on its own. Skips Top Up, Travel mode, running tasks and a Ready by within four hours.
- **MagSafe LED** (Macs that expose it): green at the limit, orange while charging. Experimental: it writes a new SMC key, and macOS gets the LED back when the helper quits.
- **Overview:** a Gauge tile (the battery's own percentage next to macOS's) and a Power flow card (charger, battery and Mac watts).
- **Ready by travel time:** enter when you need to *arrive* plus the travel time and BalDente finishes charging when you leave. Overview's Leaving card also warns when the battery is too hot (over 45 °C) for a top-up to run.
- **Automation:** `baldente://topup`, `travel/on`, `discharge/60`, `calibrate`, `lowpower/on`, `automatic`, `cancel` links (Shortcuts "Open URLs"), and `baldente get state|percent|limit|temperature|zone` for "Run Shell Script". Every link run is logged in Recent changes. There are no native Shortcuts actions yet (they need an Xcode App Intents build).
- **MagSafe LED, Custom:** pick the colour for "at the limit" and "while charging" (Default, Off, Green or Orange).
- Menu bar icon: the default size is now 30 pt (an unchanged 22 pt moves to 30 once; other sizes stay). Wave speed 1× is now half the old rate, which was too fast; the slider runs 0.2× to 6× so the old fastest speed is still reachable.
- The ring's caption ("Charging" and its bolt) in the menu bar panel is bigger: it was 4.8 pt, now at least 11.5 pt.
- Fix: new default zones are School 80%/75% and Travel 100%/95%; in the Ready by editor a day switched off could not be switched back on.

## 0.8 (pre-release)
- Updates moved to About. When a release has a BalDente.dmg attached, "Install" downloads it, checks it is BalDente at that version and correctly signed, then replaces the app and reopens it. No DMG on the release: a link to the release page instead.
- After an update BalDente checks that your zones, limits and Ready by match what the old version left, and says so (or what differs).
- Settings backups: a copy of your zones and limits is kept at every version change and before a restore (last five), with a Restore button in About.

## 0.7 (pre-release)
- What's New in About lists the changes of every version.
- Update check: General has a "Check for updates now" button and an automatic daily check (one request to GitHub, on by default, can be turned off). It only tells you; nothing installs itself.
- Updates keep your settings: zones, appearance, schedules and Ready by now load tolerantly, so a setting added in a later version can never reset the ones you already have. An unreadable config is backed up to config.unreadable.json instead of being overwritten.

## 0.6 (unreleased)
- **Update the helper after installing this version** (General → Charging helper → Update). It fixes daemon bugs listed below.
- First-run tutorial: what a charge limit is and your default limits, then a guided tour of the real window that dims everything else and points at each control in turn (zones, Top Up, Ready by, Heat Protection, the menu bar icon, Recent changes). The highlighted control stays clickable. Replay it from General, About or the Help menu.
- The defaults are shown up front, and a new install can choose "80% everywhere" instead of the zone defaults.
- While charging is held below 100%, Overview and the menu bar panel say why, with prominent Top Up and Ready by buttons one click away. Dismiss it, or it retires after a few uses.
- Habit suggestions: BalDente learns when you usually unplug and suggests a Ready by plan. Nothing changes until you tap Accept. Turn it off or clear what it learned in General.
- Accept or snooze a habit suggestion straight from its notification.
- Calibration shows its progress (step, percent, minutes left in the rest hour) on the Charging card and Overview. Cancel replaces Start Now while one is running or scheduled.
- Calibration sends a "Calibration complete" (or "cancelled") notification and the card shows when it last finished. Dates start from this version; earlier runs aren't known.
- Calibration: a "plug the charger back in" note if you unplug during the charge or rest steps; a reminder after 90 days without one (at most monthly, suggest only); History lists each calibration with health before and after and marks them on the health chart.
- History's "Health now" uses the live reading, so it matches Overview instead of the last daily log row.
- Zone suggestions: a Wi-Fi network you join regularly that no zone has is offered for a zone (or a new one). Suggest only.
- The compact layout now shows the holding hint, suggestions and Recent changes too.
- A notification for every limit change, always with the reason, with a switch per kind in General.
- Fix: in the Ready by editor a day switched off could not be switched back on.
- New default limits: School 80%/75%, Travel 100%/95% (existing installs keep their zones).
- A zone-limited Ready by that can't start because another limit is active now sends a "Ready by skipped" notification (under the Ready by switch in General).
- Overview shows a "Leaving: 7:30 AM" card within a day of a Ready by departure: when charging will start, or why it won't (wrong zone, not plugged in).
- Ready by warns when it is limited to one zone: it won't start outside that zone or under Travel Mode or Top Up.
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
