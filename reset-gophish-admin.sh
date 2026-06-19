#!/bin/bash
# Reset gophish admin login. Run as root: bash reset-gophish-admin.sh
set -euo pipefail

DB=/var/lib/gophish/gophish.db
NEW_PASS="${1:-kali-gophish}"

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root (you already have sudo su open):"
  echo "  bash /home/enviros/phish-lab/reset-gophish-admin.sh"
  exit 1
fi

if [[ ! -f "$DB" ]]; then
  echo "gophish db not found at $DB"
  exit 1
fi

HASH=$(python3 - <<PY
import bcrypt
print(bcrypt.hashpw(b"${NEW_PASS}", bcrypt.gensalt()).decode())
PY
)

sqlite3 "$DB" "UPDATE users SET hash='${HASH}', account_locked=0, password_change_required=0 WHERE username='admin';"
systemctl restart gophish
sleep 2

echo "[+] gophish admin password reset to: ${NEW_PASS}"
echo "[+] account unlocked"
echo "[+] login at https://127.0.0.1:3333  (user: admin)"
