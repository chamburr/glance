#!/usr/bin/env python3
"""Refresh the bundled Mermaid release, verifying npm's pinned SHA-512 integrity."""
import base64
import hashlib
import io
from pathlib import Path
import tarfile
import urllib.request

VERSION = "11.17.2"
INTEGRITY = "V6K3C8EBdEsPFZXSKMJe6ppQOENxuHARr9GvHX4hh47lAbhMRD9qf4oEK7LoaRQxULMa80/qt5gHO73aCleBBg=="
URL = f"https://registry.npmjs.org/mermaid/-/mermaid-{VERSION}.tgz"
ROOT = Path(__file__).resolve().parents[1] / "QLPlugin/Resources/markdown"

with urllib.request.urlopen(URL, timeout=30) as response:
    archive = response.read()
if base64.b64encode(hashlib.sha512(archive).digest()).decode() != INTEGRITY:
    raise SystemExit("Mermaid integrity verification failed")
with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as package:
    for source, target in [("package/dist/mermaid.min.js", "markdown-mermaid.min.js"),
                           ("package/LICENSE", "mermaid-LICENSE")]:
        member = package.extractfile(source)
        if member is None:
            raise SystemExit(f"Missing {source}")
        (ROOT / target).write_bytes(member.read())
print(f"Bundled Mermaid {VERSION}; SHA-512 verified")
