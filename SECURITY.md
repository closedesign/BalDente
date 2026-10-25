# Security

BalDente installs a helper (`baldented`) that runs as **root** and listens on a local Unix socket. Treat anything that
parses its input or writes SMC keys as security-sensitive.

If you find a vulnerability, please **do not open a public issue**. Use GitHub's "Report a vulnerability" button on the
Security tab of this repository (private advisory). Include what you found, how to reproduce it, and your macOS version.

## What the helper can do
Apply a charge limit and related tasks (discharge, calibration, heat protection, Low Power Mode) through SMC keys.
It does not use the network. You can remove it at any time from **General → Charging helper → Remove**.
