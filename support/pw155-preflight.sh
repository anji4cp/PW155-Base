#!/usr/bin/env bash
set -uo pipefail

root="${1:-/srv/pw155/staging/pw155}"
compat_lib="${PW155_COMPAT_LIB:-/srv/pw155/runtime/compat/lib}"
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "OK: $*"
}

if [[ ! -d "$root" ]]; then
  echo "FAIL: staging tidak ditemukan: $root" >&2
  exit 1
fi

required=(
  authd/authd
  gacd/gacd
  gamed/gs
  gamedbd/gamedbd
  gdeliveryd/gdeliveryd
  gfactiond/gfactiond
  glinkd/glinkd
  logservice/logservice
  uniquenamed/uniquenamed
)

for relative_path in "${required[@]}"; do
  binary="$root/$relative_path"
  if [[ ! -x "$binary" ]]; then
    fail "binary tidak ada atau tidak executable: $relative_path"
    continue
  fi

  if [[ -d "$compat_lib" ]]; then
    missing="$(LD_LIBRARY_PATH="$compat_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" lddtree "$binary" 2>&1 | awk '/not found/{print $1}' | sort -u | paste -sd, -)"
  else
    missing="$(lddtree "$binary" 2>&1 | awk '/not found/{print $1}' | sort -u | paste -sd, -)"
  fi
  if [[ -n "$missing" ]]; then
    fail "$relative_path kehilangan library: $missing"
  else
    pass "dependency ELF $relative_path"
  fi
done

if [[ -e "$compat_lib/libtask.so" ]]; then
  actual_hash="$(sha256sum "$compat_lib/libtask.so" | awk '{print $1}')"
  expected_hash="d82e92e97b1fe3a77c4929281d7b250bef9af81169f308165b429e14e8dfaa07"
  if [[ "$actual_hash" == "$expected_hash" ]]; then
    pass "libtask.so cocok dengan hash referensi yang diaudit"
  else
    fail "hash libtask.so tidak cocok: $actual_hash"
  fi
fi

if grep -Eq 'username="admin"[[:space:]]+password="admin"' "$root/authd/table.xml"; then
  fail "authd masih memakai kredensial database admin/admin"
else
  pass "kredensial database bawaan sudah diganti"
fi

unexpected="$(grep -RnsE '^[[:space:]]*address[[:space:]]*=[[:space:]]*0\.0\.0\.0' \
  "$root" --include='*.conf' | grep -v '/glinkd/gamesys.conf:4:' || true)"
if [[ -n "$unexpected" ]]; then
  fail "listener non-loopback tak terduga ditemukan"
  printf '%s\n' "$unexpected" >&2
else
  pass "hanya glinkd port client yang bind non-loopback"
fi

if systemctl is-active --quiet mariadb; then
  pass "MariaDB aktif"
else
  fail "MariaDB tidak aktif"
fi

if ss -lnt | grep -Eq '(^|[[:space:]])127\.0\.0\.1:3306[[:space:]]'; then
  pass "MariaDB hanya listen pada loopback"
else
  fail "MariaDB tidak terdeteksi pada 127.0.0.1:3306"
fi

if (( failures > 0 )); then
  echo "Preflight gagal: $failures masalah." >&2
  exit 1
fi

echo "Preflight lulus. Belum ada daemon PW yang dijalankan."
