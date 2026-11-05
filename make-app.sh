#!/bin/zsh
# Builds Reach.app, a real launchable menu bar app. SwiftPM makes the binary; this wraps it.
#   ./make-app.sh [debug|release] [--install]
set -e
SRC="${0:A:h}"
CONFIG="${1:-release}"
APP="$SRC/dist/Reach.app"

cd "$SRC"
swift build -c "$CONFIG" --product Reach
swift build -c "$CONFIG" --product make-icon
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Reach" "$APP/Contents/MacOS/Reach"

ICONSET="$SRC/dist/Reach.iconset"
rm -rf "$ICONSET"
"$BIN/make-icon" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Reach</string>
  <key>CFBundleDisplayName</key><string>Reach</string>
  <key>CFBundleIdentifier</key><string>com.ivanlizarde.reach</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Reach</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <!-- Menu bar only. No Dock icon, no app switcher entry. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key>
  <string>Reach watches your hand through the camera to move the pointer. Nothing is recorded or sent anywhere.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Reach listens for the sound of a fingertip tapping the screen so a tap can click. Audio is analysed live and never stored.</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

# Ad-hoc signing with a stable identifier so the camera, microphone and Accessibility
# grants survive rebuilds. Without the identifier every build is a new app to TCC.
codesign --force --deep --sign - --identifier com.ivanlizarde.reach "$APP"
echo "Built: $APP"

if [[ "$2" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Reach.app"
  cp -R "$APP" "$HOME/Applications/Reach.app"
  echo "Installed: $HOME/Applications/Reach.app"
fi
