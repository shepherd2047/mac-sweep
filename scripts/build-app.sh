#!/bin/zsh
# Builds MacSweep.app into ./dist. Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
APP=dist/MacSweep.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MacSweep "$APP/Contents/MacOS/MacSweep"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

VERSION=$(git describe --tags --always 2>/dev/null || echo 0.1)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacSweep</string>
  <key>CFBundleDisplayName</key><string>MacSweep</string>
  <key>CFBundleIdentifier</key><string>local.macsweep</string>
  <key>CFBundleExecutable</key><string>MacSweep</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>MacSweep 需要让访达移动需要管理员权限的文件（例如 App Store 安装的软件），以及清倒废纸篓。</string>
</dict>
</plist>
PLIST

# Sign with the fixed local identity (scripts/setup-signing.sh) so Full Disk Access and
# Automation grants survive rebuilds. Ad-hoc signing would make every build a "new app".
KC=~/Library/Keychains/macsweep-signing.keychain-db
[[ -f $KC ]] || ./scripts/setup-signing.sh
security unlock-keychain -p macsweep $KC
codesign --force --deep --sign "MacSweep Local Signing" --keychain $KC "$APP"
echo "built $APP ($(codesign -d -r- "$APP" 2>&1 | grep -o 'certificate leaf.*'))"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/MacSweep.app
  cp -R "$APP" ~/Applications/
  echo "installed ~/Applications/MacSweep.app"
fi
