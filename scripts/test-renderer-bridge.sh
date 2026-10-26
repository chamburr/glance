#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch="${1:?Supply task-owned scratch directory}"
mkdir -p "$scratch"
(cd HTMLConverter && go build --buildmode=c-archive -o "$scratch/htmlconverter.a")
mkdir -p "$scratch/HTMLConverter"
cp "$scratch/htmlconverter.h" "$scratch/HTMLConverter/htmlconverter.h"
cp module.modulemap "$scratch/module.modulemap"
ln -sf "$scratch/htmlconverter.a" "$scratch/libhtmlconverter.a"
xcrun swiftc -I "$scratch" -L "$scratch" QLPlugin/Utils/HTMLRenderer.swift Tests/RendererBridge/main.swift -o "$scratch/checks"
"$scratch/checks" "$scratch"
