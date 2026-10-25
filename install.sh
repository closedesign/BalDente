#!/bin/bash
# Builds BalDente, puts it in /Applications and opens it. The app then offers to install its helper (one password prompt).
set -e
cd "$(dirname "$0")"
./make_app.sh
pkill -x BalDente 2>/dev/null || true
rm -rf /Applications/BalDente.app
cp -R dist/BalDente.app /Applications/
echo "Installed /Applications/BalDente.app"
open /Applications/BalDente.app
