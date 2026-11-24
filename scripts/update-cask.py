#!/usr/bin/env python3
"""Update only SuperNav's version and SHA-256; reject accidental downgrades."""
import hashlib
import re
import sys
from pathlib import Path

cask, version, archive = sys.argv[1:]
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("Expected a stable x.y.z version")
path = Path(cask)
text = path.read_text()
current = re.search(r'^  version "(\d+\.\d+\.\d+)"$', text, re.M)
if current is None:
    raise SystemExit("Cannot identify existing cask version")
if tuple(map(int, version.split('.'))) < tuple(map(int, current[1].split('.'))):
    raise SystemExit("Refusing to downgrade the Homebrew cask")
digest = hashlib.sha256(Path(archive).read_bytes()).hexdigest()
text, versions = re.subn(r'^  version "[^"]+"$', f'  version "{version}"', text, flags=re.M)
text, hashes = re.subn(r'^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{digest}"', text, flags=re.M)
if versions != 1 or hashes != 1:
    raise SystemExit("Expected exactly one version and checksum")
path.write_text(text)
