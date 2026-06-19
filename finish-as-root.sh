#!/bin/bash
# Run inside: sudo su
set -e
if [[ $EUID -ne 0 ]]; then
  echo "Run this as root: sudo su, then bash $0"
  exit 1
fi
bash /home/enviros/phish-lab/setup-local.sh --hosts-only
echo "[+] /etc/hosts:"
grep phish.local /etc/hosts
echo "[+] Done. Test: curl -sk https://login.phish.local:8443/joZkAVhG -o /dev/null -w 'HTTP %{http_code}\n'"
