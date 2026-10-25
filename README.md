<p align="center">
  <img src="docs/images/icon.png" width="128" alt="BalDente icon">
</p>

<h1 align="center">BalDente</h1>

<p align="center">
  <b>The free, open-source battery charge limiter for macOS.</b><br>
  A free alternative to AlDente and BattOpt, with Wi-Fi zones, scheduling and a menu bar that actually tells you things.
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-blue">
  <img alt="License MIT" src="https://img.shields.io/badge/license-MIT-green">
  <a href="https://github.com/closedesign/BalDente/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/closedesign/BalDente?include_prereleases"></a>
  <a href="https://ko-fi.com/closedesign"><img alt="Support on Ko-fi" src="https://img.shields.io/badge/Ko--fi-support-ff5e5b"></a>
</p>

<p align="center">
  <a href="https://github.com/closedesign/BalDente/releases/latest"><b>⬇️ Download the latest release</b></a>
</p>

![BalDente](docs/images/social-preview.png)

## Screenshots

<table>
  <tr>
    <td><img src="docs/images/overview.png" alt="Overview: battery ring, stats and quick controls"></td>
    <td><img src="docs/images/charging.png" alt="Charging Tools: Ready by, thermometer heat limit, discharge and calibration"></td>
  </tr>
  <tr>
    <td><img src="docs/images/zones.png" alt="Zones: charge limits that follow your Wi-Fi and saved places"></td>
    <td><img src="docs/images/history.png" alt="Battery History: health advisor and charts"></td>
  </tr>
  <tr>
    <td colspan="2"><img src="docs/images/battery-display.png" alt="Battery Display: live menu bar preview and charging effect settings"></td>
  </tr>
</table>

## Why BalDente?

Keeping a MacBook at 100% all day wears the battery faster. Holding it around 80% when it is plugged in is the usual
fix, and it has been a paid feature in other apps. **BalDente does it for free, with no paid tier, no account and no
tracking.** The source is here, so you can read exactly what the helper does.

> BalDente is not affiliated with AlDente or BattOpt. "Alternative to" describes what it is for.

## Zones: automatic limits by place (free here)

> **This is the feature other battery limiters usually put behind a paid upgrade. In BalDente it is free.**

A **zone** is a charge limit that switches on by itself, based on where you are:

- **By Wi-Fi network:** add your home, school or office networks to a zone and its limit applies the moment you connect.
- **By saved place:** draw a circle on a map for places with no known Wi-Fi.
- **Each zone has its own limit and resume level**, a name, an icon and its own background color.
- **Out of the box BalDente limits charging to 50% at home** (it resumes at 45%), so a Mac that lives on its charger
  stops wearing the battery. Add your home Wi-Fi to the **Home** zone and it happens automatically. The other starter zones are
  **School** (100%), **Travel** (90%), and **Everywhere else** (80%) for anywhere that matches no zone.
- Pin any zone by hand, or tap **Automatic** to let Wi-Fi and location decide again.
- Create as many zones as you like, rename them, and back them up with **Export settings**.

## One icon for battery, network and volume (a Status Trio alternative)

BalDente's menu bar icon combines **battery, network and volume in a single icon**, the idea popularized by
[Status Trio](https://github.com/lingyired/status-trio) by lingyired (Apache-2.0). BalDente's icon design and settings are modeled on it, drawn with BalDente's own code,
and credited in [NOTICE](NOTICE). The difference is what's behind it: it is also your battery charge limiter, so **one app replaces both**,
with a charging wave animation, percentage and time remaining beside the icon, and a status panel for Wi-Fi, Bluetooth and audio.
(BalDente is not affiliated with Status Trio.)

![The live menu bar preview](docs/images/menubar-preview.png)

![Icon states: charging, charged on Ethernet, low battery, hotspot with Low Power Mode, weak Wi-Fi, no internet and muted, Wi-Fi off, Bluetooth audio](docs/images/menubar-states.png)

Ring color shows the battery state, the middle shows your connection (Wi-Fi bars, Ethernet, hotspot, a Bluetooth device, or the percentage), and the
four dots at the bottom are the volume.

## All features

**Charging control**
- Charge limit with a separate resume level (hysteresis), applied by a small root helper through the SMC.
- **Top Up to 100%** for a trip, then back to your zone's limit.
- **Travel mode:** hold 100% for 24 hours, then return to normal.
- **Ready by:** per-day schedule (days, leave time, target charge, optionally only in one zone). Charging is timed to
  finish just as you leave, and the Mac wakes itself to start when needed.
- **Calendar Ready by:** reads your next timed event (Calendar access, event start time only) and gets you full a set time before.
- **Heat Protection:** pauses charging when the battery gets hot. Limit from 30 to 60 °C, default 35 °C, set with a thermometer
  you can drag, click, or type into (↑ ↓ ← →, ⇧ for 5), with presets.
- **Discharge** to a chosen level with the charger plugged in.
- **Calibration:** drain to 15%, charge to 100%, rest an hour. Run now, at a chosen time tonight, or repeat on days of the month.
- **Low Power Mode** switch.

**Menu bar and Dock icon**
- One combined icon: battery ring, network glyph and volume dots, in the menu bar, the Dock, or both.
- Charging **wave and comet animation** (adjustable wave speed; stops with Reduce Motion), optional Dock animation, bolt pulse.
- Percentage and **time remaining** as text beside the icon; the percentage stays visible while charging.
- Ring colors by state (low is red, Low Power Mode is yellow, power is green), adjustable low-battery threshold and
  "full" level (can follow your charge limit), icon size, stroke width, number and bolt size.
- Middle slot shows Wi-Fi, Ethernet, hotspot, a Bluetooth audio device, the input source, or the percentage.
- Live preview and a gallery of icon states in settings.

**Status panel** (click the icon, or set a global shortcut)
- Battery, Network, Bluetooth, Volume, plus optional Microphone, Input Source and VPN sections, reorderable and hideable.
- Local IP address, Bluetooth device battery levels, a Bluetooth on/off switch, scroll to change volume (natural scrolling option),
  output device list.

**History and health**
- Daily log of battery health and cycle count with charts, a **Battery Health Advisor** built from Apple's published figures
  for your Mac model, and CSV export. Reset the log after a battery replacement.

**Look and feel**
- Background follows the active zone, or pick a preset, or choose your own colors; optional animation.
- **Compact mode:** a dense standard Mac layout in a small window. The regular window resizes down to about 640 x 470.
- **Search settings** with ⌘F: type a word and jump to (and highlight) the setting.
- Launch at login, status refresh interval, smart notifications (battery health drops, a helper that stopped answering),
  export and import all your settings, reset icon and panel settings.
- Command line tool: `baldente status | limit <upper> <lower> | enable | disable`.

**Free, open source, and private**
- MIT licensed, no account, no tracking, no network access from the helper. Optional donations in the app (About, Overview) and below.

## Install

1. Download `BalDente.dmg` from [Releases](https://github.com/closedesign/BalDente/releases/latest) and drag BalDente to
   Applications.
2. The app is **not notarized yet** (it is ad-hoc signed). The first time, right-click it → **Open**, or allow it in
   System Settings → Privacy & Security → **Open Anyway**.
3. Open BalDente and click **Install** under *Charging helper*. macOS asks for your password once. When an update ships
   you will see **Update Helper** and one more prompt.

Requires **macOS 26 or later**. Developed and tested on a MacBook (Mac16,1) running macOS 27. Other Macs should work, and
reports are welcome; see [Compatibility](#compatibility).

### Build it yourself

```bash
swift build                # debug build
swift test                 # unit tests
./make_app.sh --dmg        # dist/BalDente.app and dist/BalDente.dmg
./install.sh               # build, install to /Applications, launch
```

## How it works, and what it can touch

Changing the charge limit needs root, so BalDente installs a small helper, `baldented`, as a LaunchDaemon. It listens on
a local Unix socket, applies the limit through the Mac's SMC, and does nothing else: no network access, no analytics.

- **Location** access is used only to read Wi-Fi names and saved places for zone switching.
- **Calendar** access is used only for the start time of your next timed event when *Calendar Ready by* is on.
- Remove the helper any time: **General → Charging helper → Remove**.

Battery charging is a hardware-adjacent feature. Read [SECURITY.md](SECURITY.md) and the code if you want to be sure.

## Command line

```bash
baldente status            # battery %, adapter, limiter state
baldente limit 80 75       # hold at 80%, resume at 75%
baldente disable           # stop limiting
```

## Compatibility

| Mac | Status |
|---|---|
| MacBook, Apple silicon (Mac16,1), macOS 27 | Tested |
| Other Apple silicon MacBooks, macOS 26+ | Expected to work, not yet tested |
| Intel Macs, macOS 25 and older | Not tested (the app requires macOS 26) |

Different Macs expose different charging controls. If yours doesn't work, open an issue and include the output of
`swift run smcprobe`.

## Support BalDente

BalDente is free and will stay free. If it saved your battery, you can chip in:

<p>
  <a href="https://ko-fi.com/closedesign"><img alt="Support on Ko-fi" src="https://img.shields.io/badge/Ko--fi-Support%20on%20Ko--fi-ff5e5b?style=for-the-badge"></a>
  <a href="https://www.buymeacoffee.com/closedesign"><img alt="Buy me a coffee" src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-donate-ffdd00?style=for-the-badge&logoColor=black"></a>
</p>

Starring the repo and telling a friend helps just as much.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Hardware reports (your Mac model and
`smcprobe` output) are especially useful.

## Credits and license

MIT licensed, see [LICENSE](LICENSE). The menu bar icon design is modeled on
[Status Trio](https://github.com/lingyired/status-trio) (Apache-2.0); see [NOTICE](NOTICE).
