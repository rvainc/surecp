#!/usr/bin/env bash
# build-deb.sh - build build/surecp_<VERSION>_all.deb from this repository.
# Needs: dpkg-deb, help2man, gzip. Run from any directory; no root needed.
# The build is reproducible: all timestamps come from SOURCE_DATE_EPOCH
# (default: the time of the last git commit).
set -euo pipefail; export LC_ALL=C TZ=UTC

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=surecp
MAINTAINER="Viktor Rudenko <78618641+rvainc@users.noreply.github.com>"
HOMEPAGE=https://github.com/rvainc/surecp
VERSION=$(sed -n 's/^VERSION=//p' "$ROOT/$NAME")
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "cannot read VERSION from $NAME" >&2; exit 1; }
: "${SOURCE_DATE_EPOCH:=$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)}"
export SOURCE_DATE_EPOCH

OUT=$ROOT/build
PKG=$OUT/${NAME}_${VERSION}_all
DEB=$PKG.deb
rm -rf "$PKG" "$DEB"
mkdir -p "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/share/man/man1" "$PKG/usr/share/doc/$NAME"

# the program
install -m 0755 "$ROOT/$NAME" "$PKG/usr/bin/$NAME"

# man page from --help and --version (help2man uses SOURCE_DATE_EPOCH for the date)
help2man --no-info --section=1 \
  --name="copy a directory and verify the copy (rsync, metadata check, hashes)" \
  "$PKG/usr/bin/$NAME" >"$PKG/usr/share/man/man1/$NAME.1"
gzip -9n "$PKG/usr/share/man/man1/$NAME.1"

# copyright in the machine-readable format (DEP-5)
{
  printf 'Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n'
  printf 'Upstream-Name: %s\nSource: %s\n\n' "$NAME" "$HOMEPAGE"
  printf 'Files: *\nCopyright: %s\nLicense: Expat\n' "$(sed -n 's/^Copyright (c) //p' "$ROOT/LICENSE")"
  printf '\nLicense: Expat\n'
  # the license text after the copyright line, in Debian format: indent, '.' for empty lines
  sed -n '/^Permission is hereby granted/,$p' "$ROOT/LICENSE" | sed 's/^$/./; s/^/ /'
} >"$PKG/usr/share/doc/$NAME/copyright"

# changelog: a native package needs a Debian-format changelog.gz; the details are in CHANGELOG.md
{
  printf '%s (%s) unstable; urgency=medium\n\n' "$NAME" "$VERSION"
  printf '  * Release %s. See %s/blob/v%s/CHANGELOG.md\n\n' "$VERSION" "$HOMEPAGE" "$VERSION"
  printf ' -- %s  %s\n' "$MAINTAINER" "$(date -R -d "@$SOURCE_DATE_EPOCH")"
} | gzip -9n >"$PKG/usr/share/doc/$NAME/changelog.gz"

cat >"$PKG/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Architecture: all
Maintainer: $MAINTAINER
Installed-Size: $(du -sk --exclude=DEBIAN "$PKG" | cut -f1)
Depends: bash (>= 4.4), coreutils (>= 8.24), findutils (>= 4.6), rsync (>= 3.1)
Recommends: openssh-client
Suggests: b3sum, xxhash
Section: utils
Priority: optional
Homepage: $HOMEPAGE
Description: copy a directory and verify the copy
 surecp copies the contents of a directory, locally or over SSH, with rsync.
 Then it checks the copy in two independent ways: an rsync dry-run compares
 the metadata, and hashes of every file on both sides compare the content.
 Before it hashes the target, it evicts the target files from the page cache.
 .
 surecp never deletes files in the target and never overwrites a newer target
 file. It refuses system targets, detects swapped SRC/DST and an unmounted
 backup disk, and writes a manifest for later bit rot checks.
EOF

(cd "$PKG" && find usr -type f -print0 | sort -z | xargs -0 md5sum) >"$PKG/DEBIAN/md5sums"

find "$PKG" -type d -exec chmod 0755 {} +
find "$PKG" -type f -not -path "$PKG/usr/bin/*" -exec chmod 0644 {} +
find "$PKG" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
dpkg-deb --root-owner-group -Zxz --build "$PKG" "$DEB" >/dev/null
rm -rf "$PKG"
echo "$DEB"
