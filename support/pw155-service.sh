#!/usr/bin/env bash
set -euo pipefail

stage_root="${PW_STAGE_ROOT:-/srv/pw155/staging/pw155}"
runtime_root="${PW_RUNTIME_ROOT:-/srv/pw155/runtime}"
compat_lib="${PW_COMPAT_LIB:-$runtime_root/compat/lib}"
pid_root="$runtime_root/pids"
log_root="$runtime_root/logs/services"

core_services=(logservice authd uniquenamed gamedbd gacd gfactiond gdeliveryd glinkd)
default_maps=(gs01 is61)

install -d -m 0750 "$pid_root" "$log_root"

pid_file() {
  printf '%s/%s.pid\n' "$pid_root" "$1"
}

read_pid() {
  local file
  file="$(pid_file "$1")"
  [[ -s "$file" ]] && tr -cd '0-9' < "$file"
}

is_running() {
  local name="$1" pid
  pid="$(read_pid "$name" || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

wait_for_port() {
  local name="$1" port="$2" attempts="${3:-30}"
  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
      echo "[OK] $name aktif di TCP $port"
      return 0
    fi
    if ! is_running "$name"; then
      echo "[GAGAL] $name berhenti sebelum TCP $port siap." >&2
      tail -n 30 "$log_root/$name.log" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "[GAGAL] $name belum membuka TCP $port setelah $attempts detik." >&2
  return 1
}

start_process() {
  local name="$1" directory="$2" unit pid attempt executable
  shift 2

  if is_running "$name"; then
    echo "[LEWATI] $name sudah berjalan (PID $(read_pid "$name"))."
    return 0
  fi

  rm -f "$(pid_file "$name")"
  unit="pw155-game-$name.service"
  if [[ "$1" == ./* ]]; then
    executable="$stage_root/$directory/${1#./}"
    shift
    set -- "$executable" "$@"
  fi
  systemctl reset-failed "$unit" 2>/dev/null || true
  systemd-run --quiet --collect --unit="$unit" \
    --working-directory="$stage_root/$directory" \
    --setenv="LD_LIBRARY_PATH=$compat_lib" \
    --property="StandardOutput=append:$log_root/$name.log" \
    --property="StandardError=append:$log_root/$name.log" \
    --property="Restart=no" -- "$@"
  pid=""
  for ((attempt = 1; attempt <= 10; attempt++)); do
    pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] && break
    sleep 1
  done
  if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
    echo "[GAGAL] $name tidak memperoleh PID dari systemd." >&2
    systemctl --no-pager --full status "$unit" >&2 || true
    return 1
  fi
  printf '%s\n' "$pid" > "$(pid_file "$name")"
  sleep 1

  if ! is_running "$name"; then
    echo "[GAGAL] $name tidak bertahan saat startup." >&2
    tail -n 30 "$log_root/$name.log" >&2 || true
    return 1
  fi
  echo "[MULAI] $name (PID $(read_pid "$name"))."
}

start_map() {
  local name="$1"
  if [[ ! "$name" =~ ^(gs|is|arena|bg|ms|rand)[0-9]{2}$ ]]; then
    echo "Alias map tidak valid: $name" >&2
    return 2
  fi
  if ! awk -F= '/^(world_servers|instance_servers)[[:space:]]*=/{print $2}' \
      "$stage_root/gamed/gs.conf" | tr ';' '\n' | sed 's/[[:space:]]//g' | \
      grep -Fxq -- "$name"; then
    echo "Map tidak terdaftar di gs.conf: $name" >&2
    return 2
  fi

  if is_running "$name"; then
    echo "[LEWATI] $name sudah berjalan (PID $(read_pid "$name"))."
    return 0
  fi

  start_process "$name" gamed ./gs "$name" gs.conf gmserver.conf gsalias.conf
  sleep 35
  if ! is_running "$name"; then
    echo "[GAGAL] $name berhenti selama pemuatan map." >&2
    tail -n 50 "$log_root/$name.log" >&2 || true
    return 1
  fi
  echo "[OK] $name tetap aktif setelah pemuatan awal."
}

start_core() {
  if ! systemctl is-active --quiet mariadb; then
    echo "MariaDB belum aktif. Jalankan: sudo systemctl start mariadb" >&2
    exit 1
  fi

  start_process logservice logservice ./logservice logservice.conf
  wait_for_port logservice 11101

  start_process authd authd ./authd
  wait_for_port authd 29200 45

  start_process uniquenamed uniquenamed ./uniquenamed gamesys.conf
  wait_for_port uniquenamed 29401

  start_process gamedbd gamedbd ./gamedbd gamesys.conf
  wait_for_port gamedbd 29400 45

  start_process gacd gacd ./gacd gamesys.conf
  wait_for_port gacd 29702

  start_process gfactiond gfactiond ./gfactiond gamesys.conf
  wait_for_port gfactiond 29500

  start_process gdeliveryd gdeliveryd ./gdeliveryd gamesys.conf
  wait_for_port gdeliveryd 29100

  start_process glinkd glinkd ./glinkd gamesys.conf 1
  wait_for_port glinkd 29000

}

start_selected() {
  if [[ "$#" -lt 1 || "$#" -gt 6 ]]; then
    echo "Pilih 1 sampai 6 map per aksi." >&2
    return 2
  fi
  start_core
  local name
  for name in "$@"; do
    # gs.conf wajib berada sebelum gmserver.conf dan gsalias.conf.
    start_map "$name"
  done
}

start_all() {
  start_selected "${default_maps[@]}"
}

stop_one() {
  local name="$1" pid attempt unit
  unit="pw155-game-$name.service"
  pid="$(read_pid "$name" || true)"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    systemctl stop "$unit" 2>/dev/null || true
    rm -f "$(pid_file "$name")"
    echo "[LEWATI] $name sudah berhenti."
    return 0
  fi

  if systemctl is-active --quiet "$unit"; then
    systemctl stop "$unit"
  fi
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  for ((attempt = 1; attempt <= 10; attempt++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  fi
  rm -f "$(pid_file "$name")"
  echo "[STOP] $name."
}

stop_all() {
  local reverse=() file name
  shopt -s nullglob
  for file in "$pid_root"/*.pid; do
    name="$(basename "$file" .pid)"
    if [[ "$name" =~ ^(gs|is|arena|bg|ms|rand)[0-9]{2}$ ]]; then
      reverse+=("$name")
    fi
  done
  reverse+=(glinkd gdeliveryd gfactiond gacd gamedbd uniquenamed authd logservice)
  local name
  for name in "${reverse[@]}"; do
    stop_one "$name"
  done
}

status_all() {
  local name pid state
  printf '%-14s %-9s %s\n' SERVICE STATUS PID
  for name in "${core_services[@]}" "${default_maps[@]}"; do
    pid="$(read_pid "$name" || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      state=RUNNING
    else
      state=STOPPED
      pid=-
    fi
    printf '%-14s %-9s %s\n' "$name" "$state" "$pid"
  done
}

case "${1:-status}" in
  start) start_all ;;
  start-core) start_core ;;
  start-map) start_map "${2:-}" ;;
  start-selected) shift; start_selected "$@" ;;
  stop-map) stop_one "${2:-}" ;;
  stop-core) stop_all ;;
  stop) stop_all ;;
  restart) stop_all; start_all ;;
  status) status_all ;;
  *) echo "Pemakaian: $0 {start|start-core|start-map <alias>|start-selected <alias...>|stop-map <alias>|stop-core|stop|restart|status}" >&2; exit 2 ;;
esac
