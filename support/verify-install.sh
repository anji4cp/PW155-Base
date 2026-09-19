#!/usr/bin/env bash
set -uo pipefail

failures=0
check_active() {
  local unit="$1"
  if systemctl is-active --quiet "$unit"; then
    echo "OK    $unit"
  else
    echo "GAGAL $unit"
    failures=$((failures + 1))
  fi
}

check_active mariadb
check_active ssh
check_active pw155-web.service
check_active pw155-game.service
check_active pw155-db-backup.timer

if curl -fsS --max-time 10 http://127.0.0.1:8080/ >/dev/null; then
  echo "OK    panel web TCP 8080"
else
  echo "GAGAL panel web TCP 8080"
  failures=$((failures + 1))
fi

if ss -lnt | grep -Eq '(^|[[:space:]])0\.0\.0\.0:29000[[:space:]]'; then
  echo "OK    gateway game TCP 29000"
else
  echo "GAGAL gateway game TCP 29000"
  failures=$((failures + 1))
fi

sudo /srv/pw155/tools/pw155-service.sh status
echo
if (( failures == 0 )); then
  echo "Semua pemeriksaan utama lulus."
else
  echo "$failures pemeriksaan gagal."
  exit 1
fi
