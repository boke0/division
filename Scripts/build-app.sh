#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.boke0.division"
APP="$ROOT/dist/Division.app"

swift build -c release --product division
BIN="$(swift build -c release --show-bin-path)/division"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Division"
chmod +x "$APP/Contents/MacOS/Division"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Division</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Division</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSAccessibilityUsageDescription</key>
	<string>Division needs Accessibility access to move, resize, and switch application windows.</string>
</dict>
</plist>
EOF

echo "APPL????" > "$APP/Contents/PkgInfo"

# Ad-hoc, no hardened runtime: `--options runtime` disables AX unless an
# entitlement exception is present. Default ad-hoc designated requirement is a
# cdhash that changes on every rebuild, so Settings can show Division ON for an
# old binary while AXIsProcessTrusted() is false for this one. Pin csreq to the
# bundle identifier so one Accessibility grant survives rebuilds.
REQ="=designated => identifier \"${BUNDLE_ID}\""
codesign --force --sign - --identifier "$BUNDLE_ID" -r "$REQ" "$APP/Contents/MacOS/Division"
codesign --force --sign - --identifier "$BUNDLE_ID" -r "$REQ" "$APP"

echo "Built $APP"
