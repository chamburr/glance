#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app="${1:?Usage: scripts/test-previews.sh BUILT_GLANCE_APP [OUTPUT_DIRECTORY]}"
scratch="${2:-$(mktemp -d "${TMPDIR:-/tmp}/glance-tests.XXXXXX")}"
mkdir -p "$scratch/PreviewChecks.app/Contents/MacOS" "$scratch/PreviewChecks.app/Contents/Resources"
cp -R "$app/Contents/PlugIns/QLPlugin.appex/Contents/Resources/" "$scratch/PreviewChecks.app/Contents/Resources/"
cat > "$scratch/PreviewChecks.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.glance.previewchecks</string><key>CFBundleExecutable</key><string>PreviewChecks</string></dict></plist>
PLIST
ln -sf "$PWD/HTMLConverter/htmlconverter.a" "$scratch/libhtmlconverter.a"
products="$(dirname "$app")"
xcrun swiftc -I . -I "$products" -L "$scratch" -framework Cocoa -framework WebKit -lsqlite3   "$products/SwiftCSV.o" "$products/ZIPFoundation.o" "$products/SWCompression.o" "$products/BitByteData.o" \
  QLPlugin/Utils/File.swift QLPlugin/Utils/FileTree.swift QLPlugin/Utils/HTMLRenderer.swift \
  QLPlugin/Extensions/String.swift QLPlugin/Views/PreviewVC.swift QLPlugin/Views/PreviewVCFactory.swift \
  QLPlugin/Views/PreviewVCs/*.swift QLPlugin/Views/Previews/*.swift \
  Glance/Shared/Utils/Log.swift Glance/Shared/Extensions/Date.swift \
  QLPlugin/Utils/WebAsset/*.swift Glance/PreviewWindowController.swift Tests/main.swift \
  -o "$scratch/PreviewChecks.app/Contents/MacOS/PreviewChecks"
"$scratch/PreviewChecks.app/Contents/MacOS/PreviewChecks" "$scratch"
printf 'Test artifacts: %s\n' "$scratch"
