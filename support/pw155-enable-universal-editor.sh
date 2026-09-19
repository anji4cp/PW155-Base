#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Jalankan dengan sudo." >&2
  exit 1
fi

editor_user="${1:-pwadmin}"
deploy_source="${2:-/tmp/pw155-ude-deploy}"
server_root="/srv/pw155/staging/pw155"
deploy_target="/srv/pw155/tools/pw155-ude-deploy"

id "$editor_user" >/dev/null 2>&1 || { echo "User tidak ditemukan: $editor_user" >&2; exit 1; }
[[ -d "$server_root/gamed/config" ]] || { echo "Server root tidak ditemukan: $server_root" >&2; exit 1; }
[[ -f "$deploy_source" ]] || { echo "Helper deployment tidak ditemukan: $deploy_source" >&2; exit 1; }

install -o root -g root -m 0755 "$deploy_source" "$deploy_target"
install -d -o "$editor_user" -g "$editor_user" -m 0700 "/home/$editor_user/.cache/ude-upload"
install -d -o root -g root -m 0700 /var/lib/pw155-ude /var/lib/pw155-ude/backups

cat > /etc/sudoers.d/pw155-universal-editor <<EOF
${editor_user} ALL=(root) NOPASSWD: ${deploy_target} prepare *, ${deploy_target} apply *, ${deploy_target} list, ${deploy_target} rollback *, ${deploy_target} status, ${deploy_target} restart
EOF
chown root:root /etc/sudoers.d/pw155-universal-editor
chmod 0440 /etc/sudoers.d/pw155-universal-editor
visudo -cf /etc/sudoers.d/pw155-universal-editor

echo "UNIVERSAL_EDITOR_SERVER_READY user=$editor_user"
echo "Helper rollback: $deploy_target"
