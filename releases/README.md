# Release bundles

Run `./release-package.sh` from the repo root. It builds Release for **arm64** and **x86_64**, merges them with **`lipo`** into one **universal** binary, and writes **`releases/Notch Pocket-<version>.app`** (signed). Version comes from `DropZone/Info.plist`, or set **`VERSION_OVERRIDE`**.

**GitHub Actions** (`.github/workflows/release.yml`) runs on **`v*` tags** (e.g. `v0.2.0`), runs the same script, zips **`Notch-Pocket-<version>.zip`**, and attaches it to a **GitHub Release**. Built `.app` files are not committed to git.
