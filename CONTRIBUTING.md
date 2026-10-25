# Contributing

Thanks for helping! BalDente is a small Swift Package Manager project with no external dependencies.

```bash
swift build
swift test      # inside ~/Desktop use: swift test --scratch-path /tmp/baldente-build
./make_app.sh   # builds dist/BalDente.app
```

- Read `CLAUDE.md` for the architecture, performance rules (no new timers or polling) and the settings checklist.
- The daemon runs as root: keep its changes small, treat input as untrusted, and note that any change makes users update the helper.
- Please don't copy code from GPL projects (batt, Battery-Toolkit). Ideas are fine.
- Hardware reports help a lot: open an issue with your Mac model, macOS version and `swift run smcprobe` output.
