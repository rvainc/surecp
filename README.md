# surecp

[![CI](https://github.com/rvainc/surecp/actions/workflows/ci.yml/badge.svg)](https://github.com/rvainc/surecp/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`surecp` copies the contents of a directory, locally or over SSH, and then checks that the copy matches the source.

> **Use at your own risk.** `surecp` comes without any warranty. See [Disclaimer](#disclaimer).

It is one bash script around `rsync`. After the copy, it does two independent checks:

1. **Metadata:** an `rsync` dry-run must find no difference (size, mtime, permissions, owner, group, symlinks, hardlinks, ACLs, xattrs).
2. **Content:** the script hashes every file on both sides and compares the lists. Before it hashes the target, it evicts the target files from the page cache. Thus the hash reads the disk, not the RAM.

The script also writes a manifest `.surecp.sha256` into the target. You can use it later to find bit rot.

## Features

- Local → local, local → SSH, SSH → local.
- Resume and automatic retries on network errors (`rsync --partial-dir`, SSH exit code 255).
- A plan before the copy: new files, files to replace, bytes to transfer, free space.
- Guards against common mistakes:
  - a target inside the source, or the same directory;
  - swapped SRC and DST (the target has newer files → `STOP`);
  - an unmounted backup disk (a target under `/mnt` or `/media` on the root file system);
  - system targets (`/etc`, `/usr`, …) and top-level targets (`/home`, `/mnt`, `~`, …);
  - too little free space or too few free inodes;
  - two `surecp` runs into the same target (a lock).
- `--verify-only`: compare an existing copy with the source. The script does not write to the target.
- Hash tools: `sha256sum` (default), `sha512sum`, `b3sum`, `xxh128sum`. Parallel hashing with `-j`.

## Safety rules

`surecp` follows these rules by design. They describe how the script works. They are not a warranty (see [Disclaimer](#disclaimer)).


- `surecp` only reads the source.
- `surecp` never deletes a file in the target.
- `surecp` never overwrites a target file that is newer than the source file.
- `surecp` replaces an older target file only after a confirmation (or `--yes`).
- `surecp` says `OK` only when both checks pass.

## Requirements

- bash 4.4 or later, GNU coreutils, GNU findutils, `awk` (on both sides);
- `rsync` 3.1 or later (on both sides);
- the hash tool on both sides;
- for remote copies: `ssh` with key authentication. `surecp` uses `BatchMode=yes`, so a password prompt cannot work.

`surecp` runs on Linux. It needs GNU tools, so macOS and BSD are not supported.

## Installation

```bash
curl -LO https://raw.githubusercontent.com/rvainc/surecp/main/surecp
# or: git clone https://github.com/rvainc/surecp.git && cd surecp
install -m 755 surecp ~/.local/bin/surecp
surecp --version
```

## Usage

```text
surecp [OPTIONS] SRC DST        SRC/DST: /path | [user@]host:path
```

`surecp` copies the **contents** of SRC into DST, like `rsync SRC/ DST/`.

| Option | Description |
|---|---|
| `-j`, `--jobs N` | hashing processes on each side (default 1; keep 1 on HDD) |
| `-H`, `--hash CMD` | `sha256sum` \| `sha512sum` \| `b3sum` \| `xxh128sum` (default `sha256sum`) |
| `-r`, `--retries N` | retries on network errors, per operation (default 50) |
| `-V`, `--verify-only` | verify only: do not copy and do not write to the target |
| `-y`, `--yes` | answer "yes" to all confirmations (for scripts and cron) |
| `--no-xattrs` | do not copy ACLs and xattrs (for file systems without support) |
| `--allow-system-target` | allow a system or top-level target |
| `--skip-space-check` | do not stop when the free space estimate is too small |
| `-h`, `--help` | show the help |
| `--version` | show the version |
| `--` | end of options (for paths that start with `-`) |

### Examples

Copy a local directory to a backup disk:

```bash
surecp /data/photos /mnt/backup/photos
```

Copy to a server over SSH:

```bash
surecp /data/photos backup@nas:/srv/backup/photos
```

Check an existing copy one year later:

```bash
surecp --verify-only /data/photos backup@nas:/srv/backup/photos
```

Check the target against its own manifest, without the source:

```bash
cd /srv/backup/photos && sha256sum --quiet -c .surecp.sha256
```

Run from cron, with a fast hash and 4 processes on SSD:

```bash
surecp --yes -j 4 --hash xxh128sum /data /mnt/backup/data
```

### Exit status

| Code | Meaning |
|---|---|
| 0 | `OK`: the copy and both checks passed |
| 1 | an error, a refusal, `STOP` or `FAIL` (the message tells which) |
| 2 | wrong number of arguments (the script prints the usage) |
| 130, 143 | interrupted (Ctrl+C, `SIGTERM`, `SIGHUP`) |

## How it works

1. Parse and validate the options. Every value that goes into a remote command passes a whitelist or POSIX quoting.
2. Scan the source and collect statistics.
3. Preflight (not with `--verify-only`): probe the target, refuse bad targets, make a plan with two `rsync` dry-runs, check free space and inodes, ask before replacements, lock the target.
4. **Stage 1 — copy:** `rsync -aHsS -AX -u --partial-dir` with retries.
5. **Stage 2 — metadata:** `rsync -n -i`. Any output line is `FAIL`.
6. **Stage 3 — content:** evict the target files from the page cache (`sync -d`, then `dd iflag=nocache`), hash both sides in parallel, compare.
7. Write the manifest `.surecp.sha256` into the target. Remove the lock.

`surecp` keeps the mtime of the target root unchanged after its own writes (manifest, lock). Thus a later `--verify-only` run does not report the root as changed.

## Comparison

| | surecp | `rsync -c` | `rclone check` | borg / restic |
|---|---|---|---|---|
| Copy result | plain files | plain files | plain files | a repository (own format) |
| Content check | hashes of every file on both sides, after the copy | checksums decide *what to copy*; no separate check after the copy | hashes or size, after the copy | `check --read-data` checks the repository |
| Reads the target disk, not the cache | yes (best effort) | no | no | n/a |
| Metadata check after the copy (owner, mode, ACLs, xattrs, hardlinks) | yes | no | no | n/a |
| Deletes in the target | never | with `--delete` | — | prune / forget |
| Guards against swapped SRC/DST, unmounted disk | yes | no | no | n/a |
| Versioning, deduplication, encryption | no | no | no | yes |

Use `surecp` when you want a plain copy of the files that you can read without special tools, and you want a check that it matches the source. Use borg or restic when you need history, deduplication or encryption.

## Limits of the checks

- **The check is as good as the hash.** `sha256sum` and `sha512sum` are cryptographic. `xxh128sum` finds random damage, but not a deliberate attack.
- **The source can change during the run.** `surecp` hashes the source at one time. If a file changes after that, the target can contain an older version. `surecp` compares the statistics at the end and prints a warning, but it cannot see every change. Copy from a snapshot (LVM, ZFS, btrfs) for a consistent result.
- **The page cache eviction is best effort.** It uses `fadvise(DONTNEED)` per file. Pages that another process keeps mapped can stay in the cache. A RAID controller cache, a disk cache, or the ZFS ARC can also answer the read.
- **The hash proves equality now, not later.** A disk can damage the data after the check. Run `--verify-only` or `sha256sum -c .surecp.sha256` regularly.
- **Extra target files.** `surecp` never deletes them. It shows a warning only.
- **With `-j` > 1**, file paths of about 4000 bytes can mix in the pipe. The result is a false `FAIL`, never a false `OK`.
- **After a failure**, a remote hash process can continue until it ends. It only reads.
- **Not tested yet:** csh-family login shells on the remote side, real `fadvise` behaviour on every file system, the ZFS ARC.

## Development

```bash
shellcheck -S warning -e SC2088,SC2154,SC2155 surecp
bats tests/
```

`tests/ssh.bats` starts a private `sshd` on `127.0.0.1` with its own keys. It does not change `~/.ssh`. If `sshd` is not installed, these tests are skipped. One test needs root to mount a small `tmpfs`; it is skipped for a normal user.

CI (GitHub Actions) runs ShellCheck and all tests on every push and pull request.

## Disclaimer

`surecp` is free software. You use it at your own risk.

- The software comes "as is", without any warranty. The [MIT license](LICENSE) gives the full legal text.
- The authors are not responsible for data loss, damage or other problems that come from the use of `surecp`.
- Keep more than one backup. Test a restore from your backups regularly.
- Read the plan before you type "yes". Test `surecp` on data that is not critical first.

## License

[MIT](LICENSE)
