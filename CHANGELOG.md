# Changelog

## 0.2.0 — 2026-11-01

- Debian package `surecp_<version>_all.deb` with a man page (`packaging/build-deb.sh`). The build is reproducible and `lintian` finds no issues.
- CI builds, checks, installs and runs the `.deb`. Each release has the `.deb` attached.
- `--help` uses the GNU layout (`Usage:`, `Options:`) and only ASCII characters.

## 0.1.0 — 2026-11-01

First public version.

- Copy with `rsync`, resume and retries on network errors.
- Stage 2: metadata check with an `rsync` dry-run.
- Stage 3: content check with hashes of every file on both sides, after page cache eviction.
- Manifest `.surecp.sha256` in the target.
- `--verify-only`, `--jobs`, `--hash`, `--retries`, `--yes`, `--no-xattrs`, `--allow-system-target`, `--skip-space-check`, `--version`.
- Guards: target inside the source, swapped SRC/DST, unmounted backup disk, system targets, free space and inodes, lock.
- bats tests (local and SSH lab) and GitHub Actions CI.
