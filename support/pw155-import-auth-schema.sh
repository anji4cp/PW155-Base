#!/usr/bin/env bash
set -euo pipefail

source_sql="${1:-}"
database="${2:-pw}"
expected_hash="1c2000d09d222d16ab5542ee0540b933da4274598115399d6932647205ea8faf"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Jalankan sebagai root." >&2
  exit 1
fi

if [[ -z "$source_sql" || ! -f "$source_sql" ]]; then
  echo "Pemakaian: $0 /path/ke/db.sql [database]" >&2
  exit 2
fi

actual_hash="$(sha256sum "$source_sql" | awk '{print $1}')"
if [[ "$actual_hash" != "$expected_hash" ]]; then
  echo "Hash schema ditolak: $actual_hash" >&2
  exit 1
fi

mapfile -t header < <(sed -n '1,6p' "$source_sql" | sed 's/\r$//')
[[ "${header[0]}" == 'DROP DATABASE IF EXISTS pw;' ]]
[[ "${header[2]}" == 'CREATE DATABASE pw CHARACTER SET utf8 COLLATE utf8_general_ci;' ]]
[[ "${header[3]}" == "GRANT SELECT ON mysql.proc TO 'root'@'%';" ]]
[[ "${header[5]}" == 'use pw;' ]]

if ! mariadb -NBe "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${database}'" | grep -qx "$database"; then
  echo "Database tidak ditemukan: $database" >&2
  exit 1
fi

table_count="$(mariadb -NBe "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='${database}'")"
routine_count="$(mariadb -NBe "SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA='${database}'")"
if [[ "$table_count" != 0 || "$routine_count" != 0 ]]; then
  echo "Import ditolak: database tidak kosong (table=$table_count, routine=$routine_count)." >&2
  exit 1
fi

safe_sql="$(mktemp)"
trap 'rm -f "$safe_sql"' EXIT
sed '1,6d' "$source_sql" > "$safe_sql"

if grep -Eqi '^[[:space:]]*(DROP[[:space:]]+DATABASE|CREATE[[:space:]]+DATABASE|GRANT[[:space:]]|REVOKE[[:space:]]|CREATE[[:space:]]+USER|ALTER[[:space:]]+USER)' "$safe_sql"; then
  echo "Import ditolak: statement administratif tak terduga ditemukan." >&2
  exit 1
fi

mariadb "$database" < "$safe_sql"

table_count="$(mariadb -NBe "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='${database}'")"
routine_count="$(mariadb -NBe "SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA='${database}'")"
echo "Schema berhasil diimpor: table=$table_count, routine=$routine_count."
