# Release bundles

Run `./release-package.sh` from the repo root. It builds the Swift package in Release and writes **`Notch Pocket-<version>.app`** here (version from `DropZone/Info.plist`, or `VERSION_OVERRIDE`).

**GitHub Actions** (`.github/workflows/release.yml`) runs on **`v*` tags** (e.g. `v0.2.0`), builds the same bundle, zips it as **`Notch-Pocket-<version>.zip`**, and attaches it to a **GitHub Release**. Built `.app` files are not committed to git.
