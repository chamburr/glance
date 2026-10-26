#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch="${1:?Supply task-owned scratch directory}"
mkdir -p "$scratch"
xcrun swiftc QLPlugin/Utils/File.swift Tests/LocalFileGuard/main.swift -o "$scratch/checks"
"$scratch/checks" "$scratch"
