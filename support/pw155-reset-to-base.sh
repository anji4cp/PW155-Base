#!/usr/bin/env bash
set -Eeuo pipefail

# Reset only game-world state. Keep MariaDB accounts/passwords, portal, CPW,
# installer bundles, and vendor files. The old state is moved, never deleted.

usage() {
  echo "Usage: sudo bash $0 --check|--apply" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
[[ "$1" == --check || "$1" == --apply ]] || usage
[[ "${EUID}" -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

root=/srv/pw155
stage="$root/staging/pw155"
vendor="$root/vendor"
runtime="$root/runtime"
game_db="$runtime/state/gamedbd"
names_db="$runtime/state/uniquenamed"
backup_root="$runtime/reset-backups"
control_root=/var/lib/pw155-game-control
map_control_root=/var/lib/pw155-map-control
auth_env="$runtime/auth-db.env"

for path in \
  "$stage" "$vendor" "$game_db/dbhome" "$game_db/dbhomewdb" \
  "$names_db/uname"; do
  [[ -d "$path" && ! -L "$path" ]] || {
    echo "Missing directory or symlink refused: $path" >&2
    exit 1
  }
done
[[ -f "$auth_env" && ! -L "$auth_env" ]] || {
  echo "Missing auth environment: $auth_env" >&2
  exit 1
}
[[ -x "$root/tools/pw155-stage.sh" ]] || {
  echo 'Missing pw155-stage.sh.' >&2
  exit 1
}
[[ ! -L "$backup_root" ]] || {
  echo "Symlink recovery directory refused: $backup_root" >&2
  exit 1
}

for unit in \
  pw155-game.service pw155-game-control.service pw155-map-control.service \
  pw155-map-control.path pw155-character-sync.service \
  pw155-character-sync.timer pw155-web.service pw155-db-backup.timer; do
  if systemctl is-active --quiet "$unit"; then
    echo "Stop this unit before reset: $unit" >&2
    exit 1
  fi
done

running_game_units="$(systemctl list-units --type=service --state=running \
  --plain --no-legend 'pw155-game-*.service')"
[[ -z "$running_game_units" ]] || {
  echo "Game daemon still running: $running_game_units" >&2
  exit 1
}

for queue in "$control_root/requests" "$map_control_root/requests"; do
  [[ ! -L "$queue" ]] || { echo "Symlink request queue refused: $queue" >&2; exit 1; }
  if [[ -d "$queue" ]] && find "$queue" -maxdepth 1 -type f -name '*.json' \
      -print -quit | grep -q .; then
    echo "Pending requests must be inspected first: $queue" >&2
    exit 1
  fi
done
[[ ! -L "$control_root/status.json" ]] || {
  echo 'Symlink game-control status refused.' >&2
  exit 1
}

systemctl is-active --quiet mariadb || {
  echo 'MariaDB must remain active for a consistent SQL backup.' >&2
  exit 1
}

echo 'Preflight OK: game and panel writers are stopped.'
du -sh "$game_db" "$names_db" "$stage"
df -h "$runtime"
if [[ "$1" == --check ]]; then
  echo 'CHECK ONLY: no data changed.'
  exit 0
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$backup_root"
backup="$backup_root/$stamp"
mkdir -m 0700 -- "$backup"
echo "Recovery directory: $backup"
trap 'echo "RESET INTERRUPTED. Keep services stopped; old data is in $backup" >&2' ERR

dump_bin="$(command -v mariadb-dump || command -v mysqldump)"
for database in pw pw_portal; do
  "$dump_bin" --single-transaction --quick --skip-lock-tables --hex-blob \
    --routines --events --triggers "$database" | gzip -9 > "$backup/$database.sql.gz"
  gzip -t "$backup/$database.sql.gz"
done
(
  cd "$backup"
  sha256sum pw.sql.gz pw_portal.sql.gz > SHA256SUMS
)
chmod 0600 "$backup"/*.sql.gz "$backup/SHA256SUMS"
accounts_before="$(mariadb --batch --skip-column-names -e 'SELECT COUNT(*) FROM pw.users')"
admins_before="$(mariadb --batch --skip-column-names -e 'SELECT COUNT(*) FROM pw_portal.admins')"

install -d -m 0700 "$backup/state" "$backup/staging" "$backup/control"
mv -- "$game_db/dbhome" "$backup/state/dbhome"
mv -- "$game_db/dbhomewdb" "$backup/state/dbhomewdb"
mv -- "$names_db/uname" "$backup/state/uname"
install -d -m 0750 "$game_db/dbhome" "$game_db/dbhomewdb" "$names_db/uname"

# The previous role IDs must not be reused against stale portal game records.
# Login accounts and the administrator grant deliberately remain untouched.
mariadb --batch <<'SQL'
START TRANSACTION;
DELETE FROM pw.roles;
DELETE FROM pw.auth;
DELETE FROM pw.forbid;
DELETE FROM pw.iplimit;
DELETE FROM pw.point;
DELETE FROM pw.usecashlog;
DELETE FROM pw.usecashnow;
DELETE FROM pw_portal.coin_orders;
DELETE FROM pw_portal.unstuck_log;
COMMIT;
SQL

remaining_game_rows="$(mariadb --batch --skip-column-names -e \
  'SELECT (SELECT COUNT(*) FROM pw.roles) + (SELECT COUNT(*) FROM pw.auth) + (SELECT COUNT(*) FROM pw.forbid) + (SELECT COUNT(*) FROM pw.iplimit) + (SELECT COUNT(*) FROM pw.point) + (SELECT COUNT(*) FROM pw.usecashlog) + (SELECT COUNT(*) FROM pw.usecashnow) + (SELECT COUNT(*) FROM pw_portal.coin_orders) + (SELECT COUNT(*) FROM pw_portal.unstuck_log)')"
[[ "$remaining_game_rows" == 0 ]] || {
  echo "Game rows remain after reset: $remaining_game_rows" >&2
  exit 1
}
[[ "$(mariadb --batch --skip-column-names -e 'SELECT COUNT(*) FROM pw.users')" == "$accounts_before" ]]
[[ "$(mariadb --batch --skip-column-names -e 'SELECT COUNT(*) FROM pw_portal.admins')" == "$admins_before" ]]

if [[ -f "$control_root/status.json" && ! -L "$control_root/status.json" ]]; then
  mv -- "$control_root/status.json" "$backup/control/game-control-status.json"
fi

# Stage fresh vendor binaries/config at the same absolute path because the
# generated config embeds /srv/pw155/staging/pw155 in several places.
mv -- "$stage" "$backup/staging/pw155"
set -a
# shellcheck disable=SC1090
source "$auth_env"
set +a
PW_VENDOR_ROOT="$vendor" PW_RUNTIME_ROOT="$runtime" \
  "$root/tools/pw155-stage.sh" "$stage"
sed -i -E 's/^([[:space:]]*logic_threads[[:space:]]*=[[:space:]]*)[0-9]+/\11/' \
  "$stage/gamed/gs.conf"
"$root/tools/pw155-preflight.sh" "$stage"

echo 'RESET READY: fresh base and empty world state are staged.'
echo "Recovery directory: $backup"
echo 'Accounts/passwords, panel, CPW and client files were preserved.'
echo 'Game services have NOT been restarted yet.'
