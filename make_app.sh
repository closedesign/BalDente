#!/bin/bash
# Builds dist/BalDente.app (and dist/BalDente.dmg with --dmg). The app carries its own helper daemon.
set -e
cd "$(dirname "$0")"
VERSION=$(tr -d '[:space:]' < VERSION)                      # single source of truth; see CLAUDE.md "Versioning"
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)   # number of commits, so every build is distinct
[ -f Resources/AppIcon.icns ] || Tools/make_icns.sh
swift build -c release
APP=dist/BalDente.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BalDenteApp "$APP/Contents/MacOS/BalDente"
cp .build/release/baldented .build/release/baldente "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp CHANGELOG.md "$APP/Contents/Resources/"                   # What's New reads this version's section
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.baldente.app</string>
<key>CFBundleName</key><string>BalDente</string>
<key>CFBundleDisplayName</key><string>BalDente</string>
<key>CFBundleExecutable</key><string>BalDente</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>com.baldente.automation</string><key>CFBundleURLSchemes</key><array><string>baldente</string></array></dict></array>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key><string>BalDente watches the areas you save (like Home or School) so it can switch charge limits without using location constantly.</string>
<key>NSLocationAlwaysUsageDescription</key><string>BalDente watches the areas you save (like Home or School) so it can switch charge limits without using location constantly.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>BalDente reads the start time of your next event so it can have the battery charged before you leave. Event details never leave your Mac.</string>
<key>NSCalendarsUsageDescription</key><string>BalDente reads the start time of your next event so it can have the battery charged before you leave.</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>BalDente shows your Bluetooth devices, their battery levels and lets you connect or disconnect them from the status panel.</string>
<key>NSLocationUsageDescription</key><string>BalDente reads your Wi-Fi name to switch charge limits between Home, School and other zones.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>BalDente reads your Wi-Fi name to switch charge limits between Home, School and other zones.</string>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
if [ "$1" = "--dmg" ]; then
  rm -rf dist/dmg dist/BalDente.dmg; mkdir dist/dmg
  cp -R "$APP" dist/dmg/; ln -s /Applications dist/dmg/Applications
  hdiutil create -volname BalDente -srcfolder dist/dmg -ov -format UDZO dist/BalDente.dmg >/dev/null
  rm -rf dist/dmg
  echo "Built dist/BalDente.dmg"
fi
