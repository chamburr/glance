#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
products="${1:?Release products directory}"
output="${2:?Scratch output directory}"
mkdir -p "$output/Checks.app/Contents/MacOS" "$output/Checks.app/Contents/Resources"
cp -R "$products/QLPlugin.appex/Contents/Resources/" "$output/Checks.app/Contents/Resources/"
printf '%s' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.glance.slicechecks</string><key>CFBundleExecutable</key><string>Checks</string></dict></plist>' > "$output/Checks.app/Contents/Info.plist"
ln -sf "$PWD/HTMLConverter/htmlconverter.a" "$output/libhtmlconverter.a"
xcrun swiftc -I . -I "$products" -L "$output" -framework Cocoa -framework WebKit "$products/SwiftCSV.o" "$products/ZIPFoundation.o" "$products/SWCompression.o" "$products/BitByteData.o" QLPlugin/Utils/*.swift QLPlugin/Extensions/*.swift QLPlugin/Views/PreviewVC.swift QLPlugin/Views/PreviewVCFactory.swift QLPlugin/Views/PreviewVCs/*.swift QLPlugin/Views/Previews/*.swift Glance/Shared/Utils/Log.swift Glance/Shared/Extensions/Date.swift QLPlugin/Utils/WebAsset/*.swift Tests/CSV/main.swift -o "$output/Checks.app/Contents/MacOS/Checks"
"$output/Checks.app/Contents/MacOS/Checks" "$output"
