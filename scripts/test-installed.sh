#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch="$(mktemp -d "${TMPDIR:-/tmp}/glance-installed.XXXXXX")"
python3 - "$scratch" <<'PY'
from pathlib import Path
import plistlib, sqlite3, sys, zipfile
root = Path(sys.argv[1])
(root/'preview.patch').write_text('diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-old\n+new\n')
(root/'preview.md').write_text('# Preview\n\n## Diagram\n\n```mermaid\nflowchart LR\n A-->B\n```\n\n## Math\n\n$$E=mc^2$$\n')
for extension, text in [('py','print("hello")\n'),('tsx','export const App = () => <div>Hello</div>;\n'),('json','{"n":1}'),('yaml','hello: world'),('toml','hello = "world"'),('xml','<root><hello>world</hello></root>'),('tsv','a\tb\n1\t2\n')]:
    (root/f'preview.{extension}').write_text(text)
(root/'preview.plist').write_bytes(plistlib.dumps({'hello':'world'},fmt=plistlib.FMT_BINARY))
with sqlite3.connect(root/'preview.sqlite') as db:
    db.execute('CREATE TABLE sample (name TEXT)')
    db.execute("INSERT INTO sample VALUES ('hello')")
with zipfile.ZipFile(root/'preview.zip','w') as archive:
    archive.writestr('hello.txt','hello')
(root/'folder').mkdir()
(root/'folder'/'hello.txt').write_text('hello')
PY
xcrun swiftc Tests/QuickLook/main.swift -o "$scratch/probe"
/usr/bin/log stream --style compact --info --predicate 'process == "QLPlugin" AND category == "render"' > "$scratch/service.log" 2>&1 &
log_pid=$!
trap 'kill "$log_pid" 2>/dev/null || true' EXIT HUP INT TERM
"$scratch/probe" --live-check "$scratch/preview.md" "$scratch/preview.py" "$scratch/preview.tsx" \
  "$scratch/preview.json" "$scratch/preview.yaml" "$scratch/preview.toml" \
  "$scratch/preview.xml" "$scratch/preview.plist" "$scratch/preview.tsv" \
  "$scratch/preview.sqlite" "$scratch/folder" "$scratch/preview.zip" "$scratch/preview.patch"
kill "$log_pid" 2>/dev/null || true
wait "$log_pid" 2>/dev/null || true
trap - EXIT HUP INT TERM
python3 - "$scratch/service.log" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
expected = {'MarkdownPreview (.md)', 'TSVPreview (.tsv)', 'DatabasePreview (.sqlite)', 'FolderPreview (.)', 'ZIPPreview (.zip)', 'DiffPreview (.patch)'}
expected.update(f'CodePreview (.{extension})' for extension in ['py','tsx','json','yaml','toml','xml','plist'])
missing = [name for name in expected if f'Preview ready: {name}' not in text]
if missing or 'headings=3 diagrams=1 math=1' not in text or 'headings=4 diagrams=1 math=1' not in text:
    print(text)
    raise SystemExit(f'Installed preview verification failed; missing handlers: {missing}')
print('PASS: installed Quick Look service rendered all seven handler families, including Mermaid, math and live atomic-save refresh')
PY
printf 'Installed service evidence: %s\n' "$scratch/service.log"
