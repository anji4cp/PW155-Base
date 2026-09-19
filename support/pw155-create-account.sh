#!/usr/bin/env bash
set -euo pipefail

username="${1:-}"
: "${PW_ACCOUNT_PASSWORD:?Set PW_ACCOUNT_PASSWORD untuk akun game}"

if [[ ! "$username" =~ ^[A-Za-z0-9_]{3,20}$ ]]; then
  echo "Username harus 3-20 karakter: huruf, angka, atau underscore." >&2
  exit 1
fi

if [[ ! "$PW_ACCOUNT_PASSWORD" =~ ^[A-Za-z0-9_.-]{6,32}$ ]]; then
  echo "Password harus 6-32 karakter: huruf, angka, _, ., atau -." >&2
  exit 1
fi

account_name="${username,,}"
existing="$(printf "SELECT COUNT(*) FROM pw.users WHERE LOWER(name) = '%s';\n" \
  "$account_name" | sudo mariadb --batch --skip-column-names)"

if [[ "$existing" != "0" ]]; then
  echo "ALREADY_EXISTS $account_name"
  exit 0
fi

sql="
SET @account_name = '$account_name';
-- StorageEx pada authd build ini membaca VARCHAR lalu melakukan Base64.decode.
SET @account_hash = TO_BASE64(UNHEX(MD5(CONCAT(@account_name, '$PW_ACCOUNT_PASSWORD'))));
CALL pw.adduser(
  @account_name,
  @account_hash, '0', '0', 'Local Test', '0', '', '0', '0', '0', '0',
  '0', '0', '0', '1990-01-01', '0', @account_hash
);
SELECT 'CREATED' AS result, id, name, OCTET_LENGTH(passwd) AS hash_bytes
FROM pw.users WHERE LOWER(name) = @account_name;
"

printf '%s\n' "$sql" | sudo mariadb --batch --skip-column-names
unset PW_ACCOUNT_PASSWORD sql
