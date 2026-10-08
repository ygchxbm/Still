#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

configuration=${1:-debug}
if (( $# > 1 )) || [[ "$configuration" != debug && "$configuration" != release ]]; then
  print -u2 '用法：./build.sh [debug|release]'
  exit 2
fi

swift build -c "$configuration"
binary_directory=$(swift build -c "$configuration" --show-bin-path)
mkdir -p build/Still.app/Contents/MacOS
mkdir -p build/Still.app/Contents/Resources build/AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o build/Still.app/Contents/Resources/AppIcon.icns
cp "$binary_directory/Still" build/Still.app/Contents/MacOS/Still
cat > build/Still.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Still</string>
  <key>CFBundleIdentifier</key><string>local.still.app</string>
  <key>CFBundleName</key><string>Still</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.8</string>
  <key>CFBundleVersion</key><string>18</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -lint build/Still.app/Contents/Info.plist
codesign --force --sign - build/Still.app
codesign --verify --strict build/Still.app
print "已生成 $configuration 应用：$PWD/build/Still.app"
