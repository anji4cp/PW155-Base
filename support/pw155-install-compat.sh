#!/usr/bin/env bash
set -euo pipefail

source_libtask="${1:-}"
target_dir="${2:-/srv/pw155/runtime/compat/lib}"
expected_hash="d82e92e97b1fe3a77c4929281d7b250bef9af81169f308165b429e14e8dfaa07"
pcre_target="/lib/i386-linux-gnu/libpcre.so.3"

if [[ -z "$source_libtask" || ! -f "$source_libtask" ]]; then
  echo "Pemakaian: $0 /path/ke/libtask.so [target-dir]" >&2
  exit 2
fi

actual_hash="$(sha256sum "$source_libtask" | awk '{print $1}')"
if [[ "$actual_hash" != "$expected_hash" ]]; then
  echo "Hash libtask.so ditolak: $actual_hash" >&2
  exit 1
fi

elf_header="$(readelf -h "$source_libtask")"
grep -q 'Class:[[:space:]]*ELF32' <<<"$elf_header"
grep -q 'Machine:[[:space:]]*Intel 80386' <<<"$elf_header"

if [[ ! -e "$pcre_target" ]]; then
  echo "Library PCRE i386 tidak ditemukan: $pcre_target" >&2
  exit 1
fi

install -d -m 0755 "$target_dir"
install -m 0444 "$source_libtask" "$target_dir/libtask.so"
ln -sfn "$pcre_target" "$target_dir/libpcre.so.0"

echo "Compatibility library siap di $target_dir"
echo "Tidak ada daemon PW yang dijalankan."
