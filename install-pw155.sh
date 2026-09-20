#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  echo "GAGAL: $*" >&2
  exit 1
}

on_error() {
  local line="$1"
  echo "GAGAL pada baris $line. Periksa pesan tepat di atasnya." >&2
}
trap 'on_error "$LINENO"' ERR

if [[ "$(id -u)" -ne 0 ]]; then
  die "Jalankan dengan sudo: sudo bash install-pw155.sh"
fi

bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
server_archive="$bundle_dir/Perfect_World_Server_1.5.5.tar.gz"
web_archive="$bundle_dir/web.tar.gz"
client_archive="$bundle_dir/client-data.tar.gz"
deb_cache_archive="$bundle_dir/ubuntu-debs-20.04.tar.gz"
support_dir="$bundle_dir/support"

for required in \
  "$server_archive" \
  "$web_archive" \
  "$client_archive" \
  "$deb_cache_archive" \
  "$support_dir/db.sql" \
  "$support_dir/libtask.so" \
  "$support_dir/pw155-stage.sh" \
  "$support_dir/pw155-preflight.sh" \
  "$support_dir/pw155-install-compat.sh" \
  "$support_dir/pw155-service.sh" \
  "$support_dir/pw155-import-auth-schema.sh" \
  "$support_dir/pw155-verify-db.sh" \
  "$support_dir/pw155-create-account.sh" \
  "$support_dir/pw155-install-web.sh" \
  "$support_dir/pw155-backup-db.sh" \
  "$support_dir/pw155-install-backup.sh" \
  "$support_dir/pw155-game.service"; do
  [[ -f "$required" ]] || die "File paket tidak lengkap: $required"
done

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Installer ini hanya untuk Ubuntu Server."
  if [[ "${VERSION_ID:-}" != "20.04" ]]; then
    echo "PERINGATAN: paket diuji pada Ubuntu 20.04; versi ini ${VERSION_ID:-tidak diketahui}." >&2
  fi
fi

log "Mengaktifkan repository dan arsitektur 32-bit"
dpkg --add-architecture i386
if [[ -f /etc/apt/sources.list ]]; then
  sed -i -E '/^[[:space:]]*deb .*file:\/\/\/cdrom/s/^/# disabled-pwku: /' /etc/apt/sources.list
  sed -i -E '/^[[:space:]]*deb cdrom:/s/^/# disabled-pwku: /' /etc/apt/sources.list
fi

log "Memasukkan cache lokal paket Ubuntu 20.04"
tar -xzf "$deb_cache_archive" -C /var/cache/apt/archives

if ! apt-get update; then
  echo "PERINGATAN: apt update gagal; installer mencoba memakai daftar dan cache lokal." >&2
fi

log "Memasang library dan layanan yang dibutuhkan"
apt-get install -y \
  binutils file openssl ca-certificates curl rsync unzip lvm2 \
  libc6:i386 libstdc++6:i386 libgcc-s1:i386 zlib1g:i386 \
  libncurses5:i386 libssl1.1:i386 libstdc++5:i386 \
  libpcre3:i386 libxml2:i386 pax-utils \
  openjdk-8-jre-headless \
  mariadb-server mariadb-client openssh-server

systemctl enable --now ssh mariadb

log "Memperluas volume root LVM bila masih ada ruang kosong"
root_device="$(findmnt -n -o SOURCE / || true)"
if [[ "$root_device" == /dev/mapper/* ]] && command -v lvextend >/dev/null 2>&1; then
  lvextend -r -l +100%FREE "$root_device" >/dev/null 2>&1 || true
fi

work_dir="$(mktemp -d /tmp/pwku-install.XXXXXX)"
cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT
trap 'on_error "$LINENO"' ERR

log "Mengekstrak paket server dan panel web"
mkdir -p "$work_dir/server" "$work_dir/web"
tar -xzf "$server_archive" -C "$work_dir/server"
tar -xzf "$web_archive" -C "$work_dir/web"
[[ -d "$work_dir/server/Perfect_World_Server_1.5.5" ]] || die "Isi arsip server tidak sesuai."
[[ -d "$work_dir/web/web" ]] || die "Isi arsip web tidak sesuai."

install -d -m 0750 \
  /srv/pw155/vendor \
  /srv/pw155/staging/web \
  /srv/pw155/staging/client-data \
  /srv/pw155/tools \
  /srv/pw155/runtime

rsync -a "$work_dir/server/Perfect_World_Server_1.5.5/" /srv/pw155/vendor/
rsync -a "$work_dir/web/web/" /srv/pw155/staging/web/
tar -xzf "$client_archive" -C /srv/pw155/staging/client-data
chmod 0644 /srv/pw155/staging/client-data/*

log "Memasang skrip pengelolaan server"
for script in \
  pw155-stage.sh \
  pw155-preflight.sh \
  pw155-install-compat.sh \
  pw155-service.sh \
  pw155-configure-safe-revive.sh \
  pw155-import-auth-schema.sh \
  pw155-verify-db.sh \
  pw155-create-account.sh \
  pw155-install-web.sh \
  pw155-backup-db.sh \
  pw155-install-backup.sh; do
  install -m 0755 "$support_dir/$script" "/srv/pw155/tools/$script"
done

log "Menyiapkan database autentikasi dengan password acak lokal"
auth_env=/srv/pw155/runtime/auth-db.env
if [[ ! -f "$auth_env" ]]; then
  umask 077
  db_password="$(openssl rand -hex 24)"
  printf 'PW_DB_USER=pw_auth\nPW_DB_PASSWORD=%s\n' "$db_password" > "$auth_env"
fi
chown root:root "$auth_env"
chmod 0600 "$auth_env"

set -a
# shellcheck disable=SC1090
source "$auth_env"
set +a
: "${PW_DB_USER:?PW_DB_USER tidak tersedia}"
: "${PW_DB_PASSWORD:?PW_DB_PASSWORD tidak tersedia}"
[[ "$PW_DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || die "Nama user database tidak valid."
[[ "$PW_DB_PASSWORD" =~ ^[A-Za-z0-9_.-]{16,}$ ]] || die "Password database tidak valid."

mariadb --batch <<SQL
CREATE DATABASE IF NOT EXISTS pw CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS '${PW_DB_USER}'@'localhost' IDENTIFIED BY '${PW_DB_PASSWORD}';
ALTER USER '${PW_DB_USER}'@'localhost' IDENTIFIED BY '${PW_DB_PASSWORD}';
SQL

table_count="$(mariadb -NBe "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='pw'")"
routine_count="$(mariadb -NBe "SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA='pw'")"
if [[ "$table_count" == 0 && "$routine_count" == 0 ]]; then
  /srv/pw155/tools/pw155-import-auth-schema.sh "$support_dir/db.sql" pw
elif [[ "$table_count" != 8 || "$routine_count" != 19 ]]; then
  die "Database pw sudah terisi tetapi tidak sesuai (table=$table_count, routine=$routine_count)."
else
  echo "Database pw sudah siap; import schema dilewati."
fi

mariadb --batch <<SQL
GRANT SELECT ON pw.* TO '${PW_DB_USER}'@'localhost';
GRANT EXECUTE ON pw.* TO '${PW_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

log "Memasang library kompatibilitas khusus PW 1.5.5"
/srv/pw155/tools/pw155-install-compat.sh "$support_dir/libtask.so"

log "Membuat staging server yang aman"
stage_root=/srv/pw155/staging/pw155
if [[ -d "$stage_root" ]] && find "$stage_root" -mindepth 1 -print -quit | grep -q .; then
  echo "Staging sudah ada; pembuatan ulang dilewati."
else
  PW_DB_USER="$PW_DB_USER" PW_DB_PASSWORD="$PW_DB_PASSWORD" \
    /srv/pw155/tools/pw155-stage.sh "$stage_root"
fi

# Konfigurasi satu vCPU adalah baseline yang paling stabil pada VirtualBox host
# tempat paket ini disusun. Nilai ini dapat dinaikkan setelah server terbukti
# stabil pada komputer lain.
sed -i -E 's/^([[:space:]]*logic_threads[[:space:]]*=[[:space:]]*)[0-9]+/\11/' \
  "$stage_root/gamed/gs.conf"

/srv/pw155/tools/pw155-verify-db.sh
/srv/pw155/tools/pw155-preflight.sh

log "Memasang panel web, monitor, dan kontrol map"
/srv/pw155/tools/pw155-install-web.sh /srv/pw155/staging/web

log "Memasang auto-start server game"
install -m 0644 "$support_dir/pw155-game.service" /etc/systemd/system/pw155-game.service
systemctl daemon-reload
systemctl enable pw155-game.service

log "Mengaktifkan backup database harian"
/srv/pw155/tools/pw155-install-backup.sh "$support_dir/pw155-backup-db.sh"

admin_user="${PWKU_ADMIN_USER:-admin}"
[[ "$admin_user" =~ ^[A-Za-z0-9_]{3,20}$ ]] || die "PWKU_ADMIN_USER tidak valid."

log "Membuat akun administrator panel bila belum ada"
portal_admin_count="$(mariadb -NBe "SELECT COUNT(*) FROM pw_portal.accounts WHERE username=LOWER('${admin_user}')")"
if [[ "$portal_admin_count" == 0 ]]; then
  admin_password="${PWKU_ADMIN_PASSWORD:-$(openssl rand -hex 12)}"
  [[ "$admin_password" =~ ^[A-Za-z0-9_.-]{6,32}$ ]] || die "PWKU_ADMIN_PASSWORD tidak valid."
  admin_password_display="$admin_password"
  PWKU_ADMIN_USER="$admin_user" PWKU_ADMIN_PASSWORD="$admin_password" python3 <<'PY'
import http.cookiejar
import os
import re
import sys
import urllib.parse
import urllib.request

base = "http://127.0.0.1:8080"
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
html = opener.open(base + "/", timeout=20).read().decode("utf-8", "replace")
match = re.search(r'name="csrf" value="([^"]+)"', html)
if not match:
    raise SystemExit("Token CSRF registrasi tidak ditemukan")
payload = urllib.parse.urlencode({
    "csrf": match.group(1),
    "username": os.environ["PWKU_ADMIN_USER"],
    "password": os.environ["PWKU_ADMIN_PASSWORD"],
    "confirmation": os.environ["PWKU_ADMIN_PASSWORD"],
}).encode()
result = opener.open(base + "/register", payload, timeout=30).read().decode("utf-8", "replace")
if "berhasil dibuat" not in result:
    raise SystemExit("Registrasi akun admin melalui panel gagal")
PY
else
  admin_password_display="(akun sudah ada; password tidak diubah)"
  echo "Akun panel $admin_user sudah ada; registrasi dilewati."
fi

mariadb --batch <<SQL
INSERT IGNORE INTO pw_portal.admins(account_id)
SELECT ID FROM pw.users WHERE LOWER(name)=LOWER('${admin_user}');
SQL

admin_grant_count="$(mariadb -NBe "SELECT COUNT(*) FROM pw_portal.admins a JOIN pw.users u ON u.ID=a.account_id WHERE LOWER(u.name)=LOWER('${admin_user}')")"
[[ "$admin_grant_count" == 1 ]] || die "Hak administrator untuk $admin_user gagal dibuat."

log "Menyalakan seluruh daemon dan map default"
systemctl enable --now pw155-game.service
systemctl start pw155-monitor.service || true

log "Verifikasi akhir"
systemctl is-active --quiet mariadb
systemctl is-active --quiet pw155-web.service
systemctl is-active --quiet pw155-game.service
curl -fsS --max-time 20 http://127.0.0.1:8080/ >/dev/null
ss -lnt | grep -Eq '(^|[[:space:]])0\.0\.0\.0:29000[[:space:]]'
/srv/pw155/tools/pw155-service.sh status

cat <<EOF

============================================================
INSTALASI PW 1.5.5 SELESAI
============================================================
Panel web guest : http://127.0.0.1:8080
Panel VM bridge : http://IP-VM:8080
Panel host NAT  : http://127.0.0.1:8081 (jika port forwarding aktif)
Port game       : IP-VM:29000 atau 127.0.0.1:29001 (NAT)
Admin panel     : $admin_user
Password awal   : $admin_password_display

Ganti password admin setelah login pertama.
Password database dibuat acak dan hanya tersimpan di dalam guest.
Boot penuh server memerlukan sekitar 2-3 menit.
============================================================
EOF
