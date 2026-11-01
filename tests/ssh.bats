#!/usr/bin/env bats
# Copies over SSH to a private sshd on 127.0.0.1 (the "lab"). Skips when sshd is not installed.

load helpers

setup_file() {
  start_sshd
  export LAB PORT
}

teardown_file() { stop_sshd; }

setup() {
  [[ -n ${LAB:-} && -x $LAB/bin/ssh ]] || skip "sshd lab is not running"
  PATH=$LAB/bin:$PATH
  S=$BATS_TEST_TMPDIR/src D=$BATS_TEST_TMPDIR/dst
  mksrc "$S"
}

@test "ssh: copy to a remote target, then --verify-only" {
  run surecp "$S" "lab:$D"
  [ "$status" -eq 0 ]
  [[ $output == *"OK: 5 files identical"* ]]
  run surecp -V "$S" "lab:$D"
  [ "$status" -eq 0 ]
}

@test "ssh: copy from a remote source" {
  run surecp "lab:$S" "$D"
  [ "$status" -eq 0 ]
  cmp "$S/sub/deep/blob.bin" "$D/sub/deep/blob.bin"
}

@test "ssh: a path with spaces and quotes" {
  T="$BATS_TEST_TMPDIR/it's a dir"
  run surecp "$S" "lab:$T"
  [ "$status" -eq 0 ]
  [ -f "$T/a.txt" ]
}

@test "ssh: bit rot in a remote target is found" {
  surecp "$S" "lab:$D"
  flip_byte "$D/a.txt"
  run surecp -V "$S" "lab:$D"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL"* ]]
}

@test "ssh: a newer remote target file stops the copy" {
  surecp "$S" "lab:$D"
  echo new >"$D/a.txt"; touch -d '2030-01-01' "$D/a.txt"
  run surecp "$S" "lab:$D"
  [ "$status" -eq 1 ]
  [[ $output == *"STOP"* ]]
  [ "$(cat "$D/a.txt")" = new ]
}

@test "ssh: remote host that starts with '-' is refused" {
  run surecp -- "$S" "-oProxyCommand=x:$D"
  [ "$status" -eq 1 ]
  [[ $output == *"invalid host"* ]]
}

@test "ssh: one network drop is retried (rc 255)" {
  # the wrapper fails the first ssh call with 255; retry() waits 10 s and repeats it
  W=$BATS_TEST_TMPDIR/flaky; mkdir "$W"
  printf '#!/bin/sh\nif [ ! -e %s/dropped ]; then touch %s/dropped; exit 255; fi\nexec %s/ssh "$@"\n' \
    "$W" "$W" "$LAB/bin" >"$W/ssh"
  chmod +x "$W/ssh"
  PATH=$W:$PATH run surecp -r 2 "$S" "lab:$D"
  [ "$status" -eq 0 ]
  [[ $output == *"network error rc=255, retry 1/2"* ]]
  [ -e "$W/dropped" ]
}
