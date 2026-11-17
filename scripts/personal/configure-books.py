#!/usr/bin/env python3
"""Generate local, non-secret build configuration without committing library identifiers."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
app_path = root / "artifacts/dropbox-app.json"
library_path = root / "artifacts/library-source.json"
if app_path.exists() and library_path.exists():
    app = json.loads(app_path.read_text())
    library = json.loads(library_path.read_text())
    config = {"clientID": app["clientId"], "namespaceID": library["sharedFolderNamespaceId"], "folderID": library["folderId"]}
    target = root / "podcasts/Main/Books/BooksLocalConfiguration.json"
    content = json.dumps(config, indent=2) + "\n"
    if not target.exists() or target.read_text() != content:
        target.write_text(content)
    print("Local Books build configuration ready (no tokens or client secret).")
