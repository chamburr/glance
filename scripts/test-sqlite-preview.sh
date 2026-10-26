#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch="$(mktemp -d "${TMPDIR:-/tmp}/glance-preview-test.XXXXXX")"
swiftc tests/SqlitePreview/PreviewStubs.swift QLPlugin/Utils/File.swift QLPlugin/Views/Previews/DatabasePreview.swift tests/SqlitePreview/main.swift -o "$scratch/test" -lsqlite3
"$scratch/test"
