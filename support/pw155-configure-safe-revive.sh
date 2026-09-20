#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Pemakaian:
  pw155-configure-safe-revive.sh [--check|--apply] [PATH_GS_CONF]

Mode --check hanya memeriksa konfigurasi (bawaan). Mode --apply menambahkan
nocash_resurrect hanya pada [World_gs01]. Perubahan memerlukan restart map
utama sebelum berlaku.
EOF
}

mode="--check"
if [[ "${1:-}" == "--check" || "${1:-}" == "--apply" ]]; then
  mode="$1"
  shift
fi

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

gs_conf="${1:-${PW155_GS_CONFIG:-/srv/pw155/staging/pw155/gamed/gs.conf}}"
[[ -f "$gs_conf" ]] || {
  echo "gs.conf tidak ditemukan: $gs_conf" >&2
  exit 1
}

python3 - "$mode" "$gs_conf" <<'PY'
import pathlib
import re
import sys

mode = sys.argv[1]
path = pathlib.Path(sys.argv[2])
text = path.read_text(encoding="utf-8", errors="surrogateescape")

section_match = re.search(
    r"(?ms)^\[World_gs01\]\s*$.*?(?=^\[|\Z)",
    text,
)
if not section_match:
    raise SystemExit("Bagian [World_gs01] tidak ditemukan; tidak ada perubahan.")

section = section_match.group(0)
limit_match = re.search(r"(?m)^(\s*limit\s*=\s*)([^\r\n]*)$", section)
if not limit_match:
    raise SystemExit("Baris limit pada [World_gs01] tidak ditemukan; tidak ada perubahan.")

tokens = [token.strip() for token in limit_match.group(2).split(";") if token.strip()]
if "nocash_resurrect" in tokens:
    print("OK: revive item/cash yang belum aman sudah dinonaktifkan pada World_gs01.")
    raise SystemExit(0)

if mode == "--check":
    print("PERLU_PERBAIKAN: World_gs01 masih mengizinkan revive item/cash.")
    raise SystemExit(2)

tokens.append("nocash_resurrect")
new_limit = limit_match.group(1) + ";".join(tokens) + ";"
new_section = section[: limit_match.start()] + new_limit + section[limit_match.end() :]
updated = text[: section_match.start()] + new_section + text[section_match.end() :]
path.write_text(updated, encoding="utf-8", errors="surrogateescape")
print("DITERAPKAN: nocash_resurrect ditambahkan hanya pada World_gs01.")
PY
