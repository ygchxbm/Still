#!/bin/zsh
set -e
cd "${0:A:h}"
swift build -c debug
mkdir -p build/Still.app/Contents/MacOS
cp .build/debug/Still build/Still.app/Contents/MacOS/Still
cat > build/Still.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Still</string><key>CFBundleIdentifier</key><string>local.still.app</string><key>CFBundleName</key><string>Still</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - build/Still.app
