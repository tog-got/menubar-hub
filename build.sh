#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "==> Membersihkan build sebelumnya..."
rm -rf MenuBarHub.app MenuBarHub

echo "==> Mengompilasi kode Swift (Native arm64 / Apple Silicon)..."
swiftc -O -target arm64-apple-macosx12.0 \
  -framework Cocoa \
  -framework WebKit \
  -framework UserNotifications \
  Sources/Service.swift \
  Sources/NotificationBridge.swift \
  Sources/VideoDownloader.swift \
  Sources/TabManager.swift \
  Sources/MainViewController.swift \
  Sources/AppDelegate.swift \
  Sources/main.swift \
  -o MenuBarHub

echo "==> Merakit bundel MenuBarHub.app..."
mkdir -p MenuBarHub.app/Contents/MacOS
mkdir -p MenuBarHub.app/Contents/Resources

mv MenuBarHub MenuBarHub.app/Contents/MacOS/
cp Info.plist MenuBarHub.app/Contents/
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns MenuBarHub.app/Contents/Resources/
fi

echo "==> Selesai! Aplikasi berhasil dibuat di:"
echo "    $DIR/MenuBarHub.app"
