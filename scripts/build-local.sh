#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Scratch stays outside the source tree. Override to reuse an existing derived-data directory.
build_dir="${GLANCE_BUILD_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/glance-build.XXXXXX")}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
configuration="${GLANCE_CONFIGURATION:-Release}"
xcodebuild -scheme Glance -configuration "$configuration" -derivedDataPath "$build_dir" \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 ONLY_ACTIVE_ARCH=NO \
  'ARCHS=arm64 x86_64' build
app="$build_dir/Build/Products/$configuration/Glance.app"
codesign --force --sign - --entitlements QLPlugin/QLPlugin.entitlements \
  "$app/Contents/PlugIns/QLPlugin.appex"
codesign --force --sign - --entitlements Glance/Glance.entitlements "$app"
codesign --verify --strict --deep "$app"
printf '\nBuilt and ad-hoc signed: %s\n' "$app"
printf 'Check: scripts/test-previews.sh "%s"\n' "$app"
