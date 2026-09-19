#!/usr/bin/env bash
set -euo pipefail

env_file="${1:-/srv/pw155/runtime/auth-db.env}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Jalankan sebagai root agar secret lokal dapat dibaca." >&2
  exit 1
fi

if [[ ! -r "$env_file" ]]; then
  echo "File environment tidak dapat dibaca: $env_file" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

: "${PW_DB_USER:?PW_DB_USER belum diatur}"
: "${PW_DB_PASSWORD:?PW_DB_PASSWORD belum diatur}"

export MYSQL_PWD="$PW_DB_PASSWORD"
tables="$(mariadb -u "$PW_DB_USER" -NBe "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA=CHAR(112,119)")"
routines="$(mariadb -u "$PW_DB_USER" -NBe "SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA=CHAR(112,119)")"
users="$(mariadb -u "$PW_DB_USER" -NBe "SELECT COUNT(*) FROM pw.users")"
mariadb -u "$PW_DB_USER" -NBe "CALL pw.acquireuserpasswd(CHAR(95,95,112,119,49,53,53,95,112,114,111,98,101,95,95),@uid,@passwd)" >/dev/null
unset MYSQL_PWD PW_DB_PASSWORD

if [[ "$tables" != 8 || "$routines" != 19 || "$users" != 0 ]]; then
  echo "Verifikasi database gagal: table=$tables, routine=$routines, users=$users" >&2
  exit 1
fi

echo "Database OK: table=$tables, routine=$routines, users=$users; akun aplikasi dapat SELECT dan EXECUTE."
