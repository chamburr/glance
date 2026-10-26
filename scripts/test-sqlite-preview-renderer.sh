#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app="${1:?built app required}"
scratch="${2:-$(mktemp -d "${TMPDIR:-/tmp}/glance-renderer.XXXXXX")}"
mkdir -p "$scratch/RendererChecks.app/Contents/MacOS" "$scratch/RendererChecks.app/Contents/Resources"
cp -R "$app/Contents/PlugIns/QLPlugin.appex/Contents/Resources/" "$scratch/RendererChecks.app/Contents/Resources/"
printf '%s' '<plist version="1.0"><dict><key>CFBundleExecutable</key><string>RendererChecks</string><key>CFBundleIdentifier</key><string>com.glance.rendererchecks</string></dict></plist>' > "$scratch/RendererChecks.app/Contents/Info.plist"
ln -sf "$PWD/HTMLConverter/htmlconverter.a" "$scratch/libhtmlconverter.a"
xcrun swiftc -parse-as-library -I . -L "$scratch" -framework Cocoa -framework WebKit -lsqlite3 \
 QLPlugin/Utils/File.swift QLPlugin/Utils/HTMLRenderer.swift QLPlugin/Views/PreviewVC.swift \
 QLPlugin/Views/PreviewVCs/WebPreviewVC.swift QLPlugin/Utils/WebAsset/*.swift Glance/Shared/Utils/Log.swift \
 QLPlugin/Views/Previews/DatabasePreview.swift tests/SqlitePreview/SqlitePreviewRenderer.swift -o "$scratch/RendererChecks.app/Contents/MacOS/RendererChecks"
"$scratch/RendererChecks.app/Contents/MacOS/RendererChecks" "$scratch"
