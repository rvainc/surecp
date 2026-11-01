#!/usr/bin/env bats
# Local copies: SRC and DST on this machine.

load helpers

setup() {
  S=$BATS_TEST_TMPDIR/src D=$BATS_TEST_TMPDIR/dst
  mksrc "$S"
}

# --- command line ------------------------------------------------------------

@test "--version prints the version" {
  run surecp --version
  [ "$status" -eq 0 ]
  [[ $output =~ ^surecp\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--help prints the header and exits 0" {
  run surecp --help
  [ "$status" -eq 0 ]
  [[ $output == *"--verify-only"* ]]
}

@test "wrong number of arguments: usage and exit 2" {
  run surecp "$S"
  [ "$status" -eq 2 ]
}

@test "unknown flag is an error" {
  run surecp --bogus "$S" "$D"
  [ "$status" -eq 1 ]
  [[ $output == *"unknown flag"* ]]
}

@test "values outside the whitelist are refused" {
  run surecp --jobs 0 "$S" "$D";        [ "$status" -eq 1 ]
  run surecp --jobs '1;id' "$S" "$D";   [ "$status" -eq 1 ]
  run surecp --retries -1 "$S" "$D";    [ "$status" -eq 1 ]
  run surecp --hash md5sum "$S" "$D";   [ "$status" -eq 1 ]
  [ ! -e "$D" ]
}

# --- normal copy -------------------------------------------------------------

@test "copy: OK, content, links, mtimes and manifest" {
  run surecp "$S" "$D"
  [ "$status" -eq 0 ]
  [[ $output == *"OK: 5 files identical"* ]]
  cmp "$S/sub/deep/blob.bin" "$D/sub/deep/blob.bin"
  [ "$(readlink "$D/link")" = a.txt ]
  [ "$(stat -c %i "$D/a.txt")" = "$(stat -c %i "$D/hard")" ]
  [ "$(stat -c %Y "$S/a.txt")" = "$(stat -c %Y "$D/a.txt")" ]
  (cd "$D" && sha256sum --quiet -c .surecp.sha256)
  [ ! -e "$D/.surecp.lock" ]
}

@test "second run: nothing to replace, still OK" {
  surecp "$S" "$D"
  run surecp "$S" "$D"
  [ "$status" -eq 0 ]
  [[ $output == *"files to replace 0"* ]]
}

@test "--jobs 4 and other hash tools give OK" {
  run surecp -j 4 "$S" "$D";              [ "$status" -eq 0 ]
  run surecp -V --hash sha512sum "$S" "$D"; [ "$status" -eq 0 ]
  command -v b3sum >/dev/null || skip "b3sum is not installed"
  run surecp -V --hash=b3sum "$S" "$D";   [ "$status" -eq 0 ]
}

@test "path that starts with '-' after --" {
  cd "$BATS_TEST_TMPDIR"
  mv src ./-src
  run surecp -- -src -dst
  [ "$status" -eq 0 ]
  [ -f "./-dst/a.txt" ]
}

# --- verification ------------------------------------------------------------

@test "--verify-only finds bit rot (same size and mtime)" {
  surecp "$S" "$D"
  flip_byte "$D/sub/deep/blob.bin"
  run surecp --verify-only "$S" "$D"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL: 1 file(s) differ"* ]]
  [[ $output == *"sub/deep/blob.bin"* ]]
}

@test "--verify-only finds a missing file in stage 2" {
  surecp "$S" "$D"
  rm "$D/sub/b.txt"
  run surecp -V "$S" "$D"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL: metadata differs"* ]]
}

@test "--verify-only does not write to the target" {
  surecp "$S" "$D"
  rm "$D/.surecp.sha256"
  touch -r "$S" "$D"   # rm changed the root mtime; stage 2 would report ./
  before=$(cd "$D" && find . -printf '%p %y %s %T@ %m\n' | sort)
  run surecp -V "$S" "$D"
  [ "$status" -eq 0 ]
  [[ $output == *"target not modified"* ]]
  after=$(cd "$D" && find . -printf '%p %y %s %T@ %m\n' | sort)
  [ "$before" = "$after" ]
}

# --- safety rules --------------------------------------------------------------

@test "never deletes extra files in the target" {
  surecp "$S" "$D"
  echo extra >"$D/extra.txt"
  touch -d '2020-01-01' "$D"
  run surecp "$S" "$D"
  [ "$status" -eq 0 ]
  [ -f "$D/extra.txt" ]
  [[ $output == *"extra objects"* ]]
}

@test "a newer target file: STOP, the file stays unchanged" {
  surecp "$S" "$D"
  echo "edited in target" >"$D/a.txt"
  touch -d '2030-01-01' "$D/a.txt"
  run surecp "$S" "$D"
  [ "$status" -eq 1 ]
  [[ $output == *"STOP: 1 file(s) in the target are newer"* ]]
  [ "$(cat "$D/a.txt")" = "edited in target" ]
}

@test "an older target file: no terminal stops, --yes replaces" {
  surecp "$S" "$D"
  echo "old" >"$D/sub/b.txt"
  touch -d '2010-01-01' "$D/sub/b.txt"
  run surecp "$S" "$D"
  [ "$status" -eq 1 ]
  [[ $output == *"no terminal"* ]]
  [ "$(cat "$D/sub/b.txt")" = old ]
  run surecp --yes "$S" "$D"
  [ "$status" -eq 0 ]
  cmp "$S/sub/b.txt" "$D/sub/b.txt"
}

# --- refusals ----------------------------------------------------------------

@test "refuses the same directory and a target inside the source" {
  run surecp "$S" "$S/";        [ "$status" -eq 1 ]; [[ $output == *"same directory"* ]]
  run surecp "$S" "$S/sub/x";   [ "$status" -eq 1 ]; [[ $output == *"inside the source"* ]]
  [ ! -e "$S/sub/x" ]
}

@test "refuses a source without files" {
  mkdir "$BATS_TEST_TMPDIR/empty"
  run surecp "$BATS_TEST_TMPDIR/empty" "$D"
  [ "$status" -eq 1 ]
  [[ $output == *"0 files"* ]]
}

@test "refuses a source with .surecp-partial" {
  mkdir "$S/sub/.surecp-partial"
  run surecp "$S" "$D"
  [ "$status" -eq 1 ]
  [[ $output == *".surecp-partial"* ]]
}

@test "refuses control characters in names for b3sum" {
  command -v b3sum >/dev/null || skip "b3sum is not installed"
  touch "$S/bad"$'\n'"name"
  run surecp --hash b3sum "$S" "$D"
  [ "$status" -eq 1 ]
  [[ $output == *"control characters"* ]]
  run surecp "$S" "$D"
  [ "$status" -eq 0 ]
}

@test "refuses a target that is a file" {
  touch "$BATS_TEST_TMPDIR/file"
  run surecp "$S" "$BATS_TEST_TMPDIR/file/dst"
  [ "$status" -eq 1 ]
  [[ $output == *"goes through a file"* ]]
}

@test "refuses never-valid and system targets" {
  run surecp "$S" /proc/x;   [ "$status" -eq 1 ]; [[ $output == *"never a valid"* ]]
  run surecp "$S" /etc/x;    [ "$status" -eq 1 ]; [[ $output == *"--allow-system-target"* ]]
}

@test "refuses a locked target and keeps the foreign lock" {
  mkdir -p "$D/.surecp.lock"
  echo "host=other pid=1" >"$D/.surecp.lock/info"
  run surecp "$S" "$D"
  [ "$status" -eq 1 ]
  [[ $output == *"locked by another surecp run"* ]]
  [ -f "$D/.surecp.lock/info" ]
}

@test "not enough free space: stop before the copy" {
  # the 1 GiB reserve is larger than a small tmpfs; skip when no small tmpfs is available
  [ "$(id -u)" -eq 0 ] || skip "needs root to mount a tmpfs"
  mkdir "$BATS_TEST_TMPDIR/small"
  mount -t tmpfs -o size=16m tmpfs "$BATS_TEST_TMPDIR/small" 2>/dev/null || skip "cannot mount a tmpfs here"
  run surecp "$S" "$BATS_TEST_TMPDIR/small/dst"
  umount "$BATS_TEST_TMPDIR/small"
  [ "$status" -eq 1 ]
  [[ $output == *"not enough free space"* ]]
}
