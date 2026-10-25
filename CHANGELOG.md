# Changelog

## Road to 1.0
BalDente stays on 0.x until: it is notarized, it has been tested on at least three Mac models and two macOS versions, it has had a week of daily use
without a charging bug, and the helper installs, updates and uninstalls cleanly on a fresh account.

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
