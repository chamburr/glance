#!/bin/sh
set -eu
# Match the universal application so the bundled CLI also runs on Intel Macs.
output="${1:?Usage: scripts/build-cli.sh OUTPUT_DIRECTORY}"
mkdir -p "$output"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/glance-cli.XXXXXX")"
for architecture in arm64 x86_64; do
  xcrun swiftc -O -target "$architecture-apple-macos12.0" -framework AppKit -framework Quartz \
    CLI/main.swift -o "$scratch/glance-$architecture"
done
lipo -create "$scratch/glance-arm64" "$scratch/glance-x86_64" -output "$output/glance"
rm -f "$scratch/glance-arm64" "$scratch/glance-x86_64"
rmdir "$scratch"

if [ "${CODE_SIGNING_ALLOWED:-NO}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$output/glance"
fi
