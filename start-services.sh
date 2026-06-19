#!/usr/bin/env bash
# Start gophish + evilginx for local or production lab.
# Usage: sudo bash start-services.sh [local|production]
set -euo pipefail

MODE="${1:-local}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVILGINX_CFG="${EVILGINX_CFG:-/root/.evilginx}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[!] Run as root: sudo bash $0 ${MODE}"
  exit 1
fi

echo "[*] Starting gophish..."
systemctl enable gophish 2>/dev/null || true
systemctl start gophish
sleep 2
if systemctl is-active --quiet gophish; then
  echo "[+] gophish running (admin :3333, phish server :80)"
else
  echo "[!] gophish failed — check: journalctl -u gophish -n 30"
  exit 1
fi

if [[ "${MODE}" == "local" ]]; then
  bash "${SCRIPT_DIR}/setup-local.sh" --hosts-only 2>/dev/null || true
  DEV_FLAG="-developer"
else
  DEV_FLAG=""
fi

echo "[*] Starting evilginx (${MODE} mode)..."
tmux kill-session -t evilginx 2>/dev/null || true
pkill -9 evilginx2 2>/dev/null || true
sleep 1
tmux new-session -d -s evilginx "evilginx2 ${DEV_FLAG} -c ${EVILGINX_CFG}"
sleep 3

if pgrep -x evilginx2 >/dev/null; then
  echo "[+] evilginx running in tmux session 'evilginx'"
  echo "    Attach: tmux attach -t evilginx"
else
  echo "[!] evilginx failed — attach tmux or run evilginx2 manually"
  exit 1
fi

echo
echo "=== Services ==="
echo "Gophish admin : https://127.0.0.1:3333"
echo "Gophish phish : http://127.0.0.1:80"
echo "Evilginx      : tmux attach -t evilginx"
