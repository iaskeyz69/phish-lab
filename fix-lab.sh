#!/usr/bin/env bash
# Re-apply local lab fixes. Run as root.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }

install -m 644 "${SCRIPT_DIR}/phishlets/m364.yaml" /usr/share/evilginx2/phishlets/m364.yaml
rm -f /usr/share/evilginx2/phishlets/o365.yaml 2>/dev/null || true

sed -i '/evilginx.*lab/d' /etc/hosts
echo -e "\n# evilginx m364 lab\n127.0.0.1 login.phish.local www.phish.local phish.local" >> /etc/hosts

python3 <<'PY'
import json
p = "/root/.evilginx/config.json"
with open(p) as f: d = json.load(f)
d["general"].update({"domain": "phish.local", "external_ipv4": "127.0.0.1", "ipv4": "127.0.0.1",
    "https_port": 443, "dns_port": 5353, "autocert": False})
d["phishlets"] = {"m364": {"hostname": "phish.local", "enabled": True, "visible": True, "unauth_url": ""}}
if d.get("lures"): d["lures"][0].update({"phishlet": "m364", "redirect_url": "https://www.phish.local"})
with open(p, "w") as f: json.dump(d, f, indent=2)
PY

bash "${SCRIPT_DIR}/start-services.sh" local
echo "Lure: https://login.phish.local$(python3 -c "import json; print(json.load(open('/root/.evilginx/config.json'))['lures'][0]['path'])")"
