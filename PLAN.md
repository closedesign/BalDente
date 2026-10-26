# BalDente: free, open-source BattOpt + AlDente alternative

License: MIT. Reference projects (read for ideas and SMC key behavior; check each license before copying code):
actuallymentor/battery (MIT), charlie0129/batt (GPL-2.0), mhaeuser/Battery-Toolkit (GPL). BattOpt is closed source; do not use it.

## Architecture
- `CSMC` (C): AppleSMC read/write. Done, reads work as a normal user.
- `BalDenteCore` (Swift): config, zones, limiter policy, Wi-Fi detection, battery info.
- `baldented` (root LaunchDaemon): applies the limit, listens on a Unix socket.
- `baldente` (CLI): talks to the daemon.
- `BalDente.app` (SwiftUI MenuBarExtra): zones UI, status, extras.

## Milestones
1. [x] SMC layer + probe (`swift run smcprobe`)
2. [ ] Daemon + CLI limiter (backend chosen from the keys the probe finds)
3. [ ] Zones (Wi-Fi/BSSID/gateway detection, override, notifications)
4. [ ] Menu bar GUI + settings
5. [x] AlDente extras: sailing, heat protection, top up, discharge, calibration, sleep handling (sleep, LED and scheduled tasks need testing on real hardware)
6. [ ] Packaging: .app bundle, SMAppService helper registration, uninstaller

## Findings on this Mac (Mac16,1, macOS 27.0.1)
- Legacy keys CH0B / CH0C / CHTE / CH0I: not present.
- bfF0 / bfD0 / bfE0 / CH0J: exist but are root-only (NotPrivileged for a normal user).
- So this machine likely uses the firmware-limit backend, with Apple gating on newer macOS 27 betas.
