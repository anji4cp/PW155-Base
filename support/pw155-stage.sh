#!/usr/bin/env bash
set -euo pipefail

vendor_root="${PW_VENDOR_ROOT:-/srv/pw155/vendor}"
stage_root="${1:-/srv/pw155/staging/pw155}"
runtime_root="${PW_RUNTIME_ROOT:-/srv/pw155/runtime}"

if [[ ! -d "$vendor_root" ]]; then
  echo "Vendor source tidak ditemukan: $vendor_root" >&2
  exit 1
fi

if [[ -e "$stage_root" ]] && find "$stage_root" -mindepth 1 -print -quit | grep -q .; then
  echo "Tujuan staging sudah berisi data: $stage_root" >&2
  echo "Gunakan direktori baru agar deployment lama tidak tertimpa." >&2
  exit 1
fi

install -d -m 0750 "$stage_root"
rsync -a --chmod=D750,F640 "$vendor_root/" "$stage_root/"

executables=(
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

for relative_path in "${executables[@]}"; do
  if [[ ! -f "$stage_root/$relative_path" ]]; then
    echo "Binary wajib tidak ditemukan: $relative_path" >&2
    exit 1
  fi
  chmod 0750 "$stage_root/$relative_path"
done

# Semua listener internal dibatasi ke loopback terlebih dahulu.
while IFS= read -r -d '' config_file; do
  perl -pi -e 's/^(\s*address\s*=\s*)0\.0\.0\.0(\s*)$/${1}127.0.0.1$2/' "$config_file"
done < <(find "$stage_root" -type f -name '*.conf' -print0)

# Hanya endpoint client pertama glinkd yang mendengarkan di interface guest.
perl -0pi -e 's/(\[GLinkServer1\][^\[]*?\n\s*address\s*=\s*)127\.0\.0\.1/${1}0.0.0.0/s' \
  "$stage_root/glinkd/gamesys.conf"

# Jangan menulis log ke layout vendor lama /home. Semua state runtime berada
# di luar staging agar mudah dibackup dan tidak mencampur binary dengan log.
install -d -m 0750 "$runtime_root/logs/logservice"
export PW_RUNTIME_ROOT_REWRITE="$runtime_root"
perl -pi -e 's#^(\s*fd_\w+\s*=\s*)/home/logservice/logs/#$1$ENV{PW_RUNTIME_ROOT_REWRITE}/logs/logservice/#' \
  "$stage_root/logservice/logservice.conf"
unset PW_RUNTIME_ROOT_REWRITE

# Redirect state dan backup daemon dari layout vendor /home ke runtime proyek.
install -d -m 0750 \
  "$runtime_root/logs/authd" \
  "$runtime_root/state/gamedbd/dbhome" \
  "$runtime_root/state/gamedbd/dbhomewdb" \
  "$runtime_root/state/uniquenamed/uname" \
  "$runtime_root/backups/gamedbd" \
  "$runtime_root/backups/uniquenamed"

export PW_RUNTIME_ROOT_REWRITE="$runtime_root"
export PW_STAGE_ROOT_REWRITE="$stage_root"
perl -pi -e 's#/home/authd/mtrace\.authd#$ENV{PW_RUNTIME_ROOT_REWRITE}/logs/authd/mtrace.authd#' \
  "$stage_root/authd/authd.conf"
perl -pi -e 's#/home/gamedbd/dbhomewdb#$ENV{PW_RUNTIME_ROOT_REWRITE}/state/gamedbd/dbhomewdb#g; s#/home/gamedbd/dbhome#$ENV{PW_RUNTIME_ROOT_REWRITE}/state/gamedbd/dbhome#g; s#/home/gamedbd/backup#$ENV{PW_RUNTIME_ROOT_REWRITE}/backups/gamedbd#g' \
  "$stage_root/gamedbd/gamesys.conf"
perl -pi -e 's#/home/uniquenamed/unamebackup#$ENV{PW_RUNTIME_ROOT_REWRITE}/backups/uniquenamed#g; s#/home/uniquenamed/uname#$ENV{PW_RUNTIME_ROOT_REWRITE}/state/uniquenamed/uname#g' \
  "$stage_root/uniquenamed/gamesys.conf"
perl -pi -e 's#/home/gamed/config/?#$ENV{PW_STAGE_ROOT_REWRITE}/gamed/config/#g' \
  "$stage_root/gamed/gs.conf" "$stage_root/gamed/gsalias.conf"
# Guest development memakai 2 vCPU. Konfigurasi vendor meminta 8 logic thread
# dan dapat membuat guest tidak responsif setelah map utama aktif.
perl -pi -e 's/^(\s*logic_threads\s*=\s*)\d+/${1}2/' \
  "$stage_root/gamed/gs.conf"
unset PW_RUNTIME_ROOT_REWRITE PW_STAGE_ROOT_REWRITE

# Kredensial database harus diberikan sebagai environment dan tidak memiliki
# karakter yang membutuhkan XML escaping.
: "${PW_DB_USER:?Set PW_DB_USER sebelum menjalankan staging}"
: "${PW_DB_PASSWORD:?Set PW_DB_PASSWORD sebelum menjalankan staging}"

if [[ ! "$PW_DB_USER" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "PW_DB_USER hanya boleh berisi huruf, angka, dan underscore." >&2
  exit 1
fi

if [[ ! "$PW_DB_PASSWORD" =~ ^[A-Za-z0-9_.-]{16,}$ ]]; then
  echo "PW_DB_PASSWORD minimal 16 karakter: huruf, angka, _, ., atau -." >&2
  exit 1
fi

export PW_DB_USER PW_DB_PASSWORD
perl -0pi -e 's/username="[^"]*"\s+password="[^"]*"/username="$ENV{PW_DB_USER}" password="$ENV{PW_DB_PASSWORD}"/' \
  "$stage_root/authd/table.xml"
# Connector/J 5.1.10 mencoba membaca metadata body stored procedure. Akun
# aplikasi sengaja tidak diberi akses ke tabel sistem; minta driver memakai
# definisi parameter dari pemanggilan yang sudah dideklarasikan table.xml.
perl -0pi -e 's#(jdbcCompliantTruncation=false)(?!&amp;noAccessToProcedureBodies=true)#$1&amp;noAccessToProcedureBodies=true#' \
  "$stage_root/authd/table.xml"
chmod 0640 "$stage_root/authd/table.xml"

echo "Staging aman dibuat di: $stage_root"
echo "Binary belum dijalankan. Jalankan pw155-preflight.sh sebelum start service."
