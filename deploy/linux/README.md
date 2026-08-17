# Linux VPS deployment

Runs the unchanged Tauri application inside an isolated Xvfb desktop and serves
that desktop over noVNC on loopback port `3021`. The mint engine and Tauri IPC
are identical to the Windows build — only the display is virtual.

**No desktop environment is required on the server.** A plain terminal-only
Ubuntu VPS is the expected target.

## Install (recommended)

One command on a fresh server. It pulls the prebuilt binary from GitHub
Releases — no Rust toolchain, no compile:

```bash
curl -fsSL https://raw.githubusercontent.com/ramirezoffc/minter-rr/main/deploy/linux/install.sh | sudo bash
```

GitHub does not treat prereleases as the stable `latest` release. Install this
beta explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/ramirezoffc/minter-rr/main/deploy/linux/install.sh |
  sudo MINTER_VERSION=v0.3.0-beta.1 bash
```

It installs runtime packages, verifies the download against the published
SHA256, creates the `minter` service user, sets up systemd + noVNC, asks for a
VNC password, and prints exactly how to connect.

Re-running it upgrades in place: the previous binary is kept under
`/opt/minter/backups/`, and it refuses to replace a build while a mint looks
active (override with `MINTER_FORCE=1`).

Useful variables:

| Variable | Purpose |
|---|---|
| `MINTER_VERSION=v0.3.0-beta.1` | install a specific tag instead of the latest stable release |
| `MINTER_REPO=owner/repository` | override the default `ramirezoffc/minter-rr` release source |
| `MINTER_VNC_PASSWORD=…` | non-interactive install |
| `MINTER_FORCE=1` | replace the binary even if a mint looks active |

## Install from source (alternative)

Only needed to run unreleased code. Requires the full build toolchain:

```bash
sudo apt-get install build-essential pkg-config curl ca-certificates git file wget \
  libwebkit2gtk-4.1-dev libxdo-dev libssl-dev \
  libayatana-appindicator3-dev librsvg2-dev patchelf \
  xvfb xauth x11-utils x11vnc openbox dbus-x11 novnc websockify \
  xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk \
  pcmanfm fonts-dejavu-core

cargo build -p minter-desktop --release
sudo ./deploy/linux/install-built.sh 'eight-or-more-characters'
```

The VPS needs **no desktop environment** — Xvfb provides a virtual display, so a
plain terminal-only Ubuntu server is the expected target.

## Reaching the GUI

The service listens on `127.0.0.1:3021` only. That is deliberate and must stay
that way: the noVNC layer is protected by a classic VNC password, and classic
VNC auth uses **only the first 8 characters** — see `x11vnc -storepasswd` in
`install-built.sh`. That is not a credential you can put on the open Internet in
front of a wallet GUI. Always reach it through a tunnel.

### Option 1 — SSH tunnel (nothing extra to install)

Windows 10/11, macOS and Linux all ship an SSH client. From your own machine:

```bash
ssh -f -N -L 3021:127.0.0.1:3021 -o ExitOnForwardFailure=yes user@YOUR_VPS_IP
```

Then open <http://127.0.0.1:3021/vnc.html?autoconnect=1&resize=scale>.

Nothing is exposed publicly: the port stays bound to loopback on both ends.
If the page does not load, check the tunnel first (`Get-NetTCPConnection
-LocalPort 3021` on Windows, `ss -ltn | grep 3021` elsewhere) before touching
the service.

### Option 2 — Tailscale (easiest for non-technical operators)

Install Tailscale on the VPS and on your own machine, log both into the same
account, then browse to `http://<vps-tailscale-name>:3021/vnc.html`. To have
Tailscale terminate TLS for you:

```bash
sudo tailscale serve --bg 3021
```

Still no public ports: the tailnet is private to your account.

### Do not

Publishing port 3021 with a reverse proxy and no real authentication puts an
unlocked-wallet GUI one weak password away from anyone scanning the Internet.
If you need browser access without a VPN client, put an authenticating proxy in
front of it (Cloudflare Access, oauth2-proxy, or similar) — never bare noVNC.

Runtime files are under `/var/lib/minter`: `keys.vault`, `config.json`, tasks,
auth cache, results, and logs. Files copied to `/var/lib/minter/imports` can be
selected from the application's native server-side file picker.

Operations:

```bash
sudo systemctl status minter-vps
sudo journalctl -u minter-vps -f
sudo systemctl restart minter-vps
```

## VPS rendering fallbacks

The default profile uses XDamage, `x11vnc -wait 5 -defer 5`, WebKit
compositing, and does not force software GL. The WebKit DMABUF renderer remains
disabled because it is unreliable under Xvfb.

If a particular VPS shows a black WebView, rendering artifacts, or stale
frames, add a systemd override with the conservative fallbacks:

```ini
[Service]
Environment=MINTER_VNC_NOXDAMAGE=1
Environment=MINTER_SOFTWARE_RENDERING=1
Environment=MINTER_WEBKIT_DISABLE_COMPOSITING=1
```

Create the override with `sudo systemctl edit minter-vps`, then run
`sudo systemctl restart minter-vps`. Available runtime variables are:

| Variable | Default | Meaning |
|---|---:|---|
| `MINTER_VNC_WAIT` | `5` | x11vnc update wait in milliseconds (`0..1000`) |
| `MINTER_VNC_DEFER` | `5` | x11vnc deferred-update delay in milliseconds (`0..1000`) |
| `MINTER_VNC_NOXDAMAGE` | `0` | set to `1` to disable XDamage |
| `MINTER_SOFTWARE_RENDERING` | `0` | set to `1` to force software GL |
| `MINTER_WEBKIT_DISABLE_COMPOSITING` | `0` | set to `1` for the conservative WebKit workaround |
| `MINTER_WEBKIT_DISABLE_DMABUF` | `1` | set to `0` to re-enable the WebKit DMABUF renderer |
| `MINTER_SCREEN` | `1440x900x24` | Xvfb screen geometry and depth |

Boolean variables accept only `0` or `1`; invalid values stop the launcher
instead of being passed to x11vnc.
