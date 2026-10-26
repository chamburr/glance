#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app="${1:?Usage: scripts/test-web-modernization.sh BUILT_APP OUTPUT_DIRECTORY}"
scratch="${2:?Supply task-owned output directory}"
mkdir -p "$scratch/Checks.app/Contents/MacOS" "$scratch/Checks.app/Contents/Resources"
cp -R "$app/Contents/PlugIns/QLPlugin.appex/Contents/Resources/" "$scratch/Checks.app/Contents/Resources/"
cat > "$scratch/Checks.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.glance.slicechecks</string><key>CFBundleExecutable</key><string>Checks</string></dict></plist>
PLIST
xcrun swiftc -framework Cocoa -framework WebKit \
 QLPlugin/Utils/File.swift QLPlugin/Views/PreviewVC.swift \
 QLPlugin/Views/PreviewVCs/WebPreviewVC.swift QLPlugin/Utils/WebAsset/*.swift \
 Glance/Shared/Utils/Log.swift Tests/WebModernization/main.swift \
 -o "$scratch/Checks.app/Contents/MacOS/Checks"
"$scratch/Checks.app/Contents/MacOS/Checks" "$scratch"
