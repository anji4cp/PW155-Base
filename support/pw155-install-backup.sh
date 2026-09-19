#!/usr/bin/env bash
set -euo pipefail

source_script="${1:-/srv/pw155/staging/scripts/pw155-backup-db.sh}"
target_script="/srv/pw155/tools/pw155-backup-db.sh"

if [[ "$EUID" -ne 0 ]]; then
  echo "Jalankan installer backup dengan sudo." >&2
  exit 1
fi
if [[ ! -f "$source_script" ]]; then
  echo "Script backup tidak ditemukan: $source_script" >&2
  exit 1
fi

install -d -o root -g root -m 0755 /srv/pw155/tools
install -d -o root -g root -m 0700 /srv/pw155/backups/database
install -o root -g root -m 0750 "$source_script" "$target_script"

cat > /etc/systemd/system/pw155-db-backup.service <<'UNIT'
[Unit]
Description=PW155 consistent MariaDB backup
After=mariadb.service
Requires=mariadb.service

[Service]
Type=oneshot
User=root
Group=root
Environment=PW155_BACKUP_ROOT=/srv/pw155/backups/database
Environment=PW155_BACKUP_RETENTION_DAYS=14
ExecStart=/srv/pw155/tools/pw155-backup-db.sh
Nice=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=/srv/pw155/backups/database
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/pw155-db-backup.timer <<'UNIT'
[Unit]
Description=Run PW155 database backup every day at 03:30 WIB

[Timer]
OnCalendar=*-*-* 20:30:00 UTC
Persistent=true
RandomizedDelaySec=10m
Unit=pw155-db-backup.service

[Install]
WantedBy=timers.target
UNIT

chmod 0644 /etc/systemd/system/pw155-db-backup.service \
  /etc/systemd/system/pw155-db-backup.timer
systemctl daemon-reload
systemctl enable --now pw155-db-backup.timer
systemctl start pw155-db-backup.service
systemctl --no-pager --full status pw155-db-backup.service | sed -n '1,14p' || true
systemctl list-timers pw155-db-backup.timer --no-pager
