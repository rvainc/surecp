# Shared helpers for the surecp bats tests.

SURECP="$BATS_TEST_DIRNAME/../surecp"

# surecp ARGS... — run the script without a terminal (setsid -w): a confirmation then stops with "no terminal"
surecp() { setsid -w bash "$SURECP" "$@"; }

# mksrc DIR — a small source tree: regular files, a subdirectory, a symlink, a hardlink, an empty file
mksrc() {
  mkdir -p "$1/sub/deep"
  printf 'alpha\n' >"$1/a.txt"
  printf 'beta\n' >"$1/sub/b.txt"
  head -c 300000 /dev/urandom >"$1/sub/deep/blob.bin"
  : >"$1/empty"
  ln -s a.txt "$1/link"
  ln "$1/a.txt" "$1/hard"
  touch -d '2020-01-01 00:00:00' "$1/a.txt" "$1/sub/b.txt"
}

# flip_byte FILE — change one byte, keep the size and the mtime (simulates bit rot)
flip_byte() {
  local m; m=$(stat -c %y -- "$1")
  printf 'X' | dd of="$1" bs=1 seek=0 conv=notrunc status=none
  touch -d "$m" -- "$1"
}

# start_sshd — a private sshd on 127.0.0.1 with its own keys; puts an ssh wrapper first in PATH.
# Never touches ~/.ssh. Skips the test when sshd or ssh-keygen is not available.
start_sshd() {
  local sshd; sshd=$(command -v sshd || echo /usr/sbin/sshd)
  if [[ ! -x $sshd ]] || ! command -v ssh-keygen >/dev/null; then skip "sshd is not installed"; fi
  LAB=$BATS_FILE_TMPDIR/lab
  mkdir -p "$LAB/bin"
  ssh-keygen -q -t ed25519 -N '' -f "$LAB/host_key"
  ssh-keygen -q -t ed25519 -N '' -f "$LAB/user_key"
  cp "$LAB/user_key.pub" "$LAB/authorized_keys"
  chmod 700 "$LAB"; chmod 600 "$LAB/authorized_keys"
  PORT=$((20000 + RANDOM % 20000))
  cat >"$LAB/sshd_config" <<EOF
ListenAddress 127.0.0.1
Port $PORT
HostKey $LAB/host_key
AuthorizedKeysFile $LAB/authorized_keys
PidFile $LAB/sshd.pid
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
EOF
  cat >"$LAB/ssh_config" <<EOF
Host lab
  HostName 127.0.0.1
  Port $PORT
  User $(id -un)
  IdentityFile $LAB/user_key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
  # the script calls plain "ssh": the wrapper adds the lab config
  printf '#!/bin/sh\nexec %s -F %s "$@"\n' "$(command -v ssh)" "$LAB/ssh_config" >"$LAB/bin/ssh"
  chmod +x "$LAB/bin/ssh"
  "$sshd" -f "$LAB/sshd_config" -E "$LAB/sshd.log"

  for _ in $(seq 50); do
    "$LAB/bin/ssh" -o BatchMode=yes lab true 2>/dev/null && return 0
    sleep 0.1
  done
  cat "$LAB/sshd.log" >&2
  return 1
}

stop_sshd() {
  if [[ -n ${LAB:-} && -f $LAB/sshd.pid ]]; then kill "$(cat "$LAB/sshd.pid")" 2>/dev/null || true; fi
}
