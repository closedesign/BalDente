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

<!-- Add screenshots here once captured: docs/images/overview.png, charging.png, zones.png, history.png -->

## Why BalDente?

Keeping a MacBook at 100% all day wears the battery faster. Holding it around 80% when it is plugged in is the usual
fix, and it has been a paid feature in other apps. **BalDente does it for free, with no paid tier, no account and no
tracking.** The source is here, so you can read exactly what the helper does.

> BalDente is not affiliated with AlDente or BattOpt. "Alternative to" describes what it is for.

## Features

- **Charge limit with zones.** Pick a limit (and where charging resumes) for home, work, or anywhere else. BalDente
  switches automatically by Wi-Fi network or saved place, and you can pin a zone by hand.
- **Top Up and Travel mode.** Charge to 100% for a trip, then go back to your limit. Travel mode holds 100% for 24 hours.
- **Ready by.** Tell it when you leave and how full you want to be; it times the charge. **Calendar Ready by** reads your
  next timed event so it can do it for you.
- **Heat Protection.** Pauses charging when the battery gets hot (30 to 60 °C, default 35 °C), with a thermometer you can
  drag, click, or type into.
- **Discharge and Calibration.** Drain to a target while plugged in, or run a full calibration cycle now, tonight, or
  monthly.
- **Low Power Mode** switch, a **battery history** page with health and cycle charts, and **health advice**.
- **A menu bar icon that shows more.** A battery ring, network and volume in one icon, with a charging wave (speed is
  adjustable), the percentage and time remaining beside it, and a status panel for Wi-Fi, Bluetooth and audio.
- **Settings search** (⌘F), a compact layout, a Dock icon option and a command line tool.

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
