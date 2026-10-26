#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch="$(mktemp -d "${TMPDIR:-/tmp}/glance-markdown-checks.XXXXXX")"
xcrun swiftc -framework Cocoa -framework WebKit QLPlugin/Views/Previews/MarkdownPreview.swift Tests/MarkdownImages/main.swift -o "$scratch/checks"
"$scratch/checks" "$scratch"
