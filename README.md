# dmdfami/mac

One-command full remote control for any Mac. Named Cloudflare Tunnel + SSH + VNC + SMB + AppleScript automation — no SIP modification needed.

## Quick Start

```bash
# On the Mac you want to control remotely:
npx dmdfami/mac

# On your main Mac, install the manager:
curl -fsSL https://raw.githubusercontent.com/dmdfami/mac/main/bin/mac -o ~/bin/mac && chmod +x ~/bin/mac
```

## What `npx dmdfami/mac` Sets Up

| Feature | Details |
|---------|---------|
| SSH + key auth | ED25519 key, Remote Login enabled |
| Named CF Tunnel | Permanent hostname (`<name>.hcply.com`), LaunchDaemon, auto-restart |
| SSH via tunnel | `<name>.hcply.com` — TCP proxy through Cloudflare |
| VNC via tunnel | `vnc-<name>.hcply.com` — Screen Sharing through Cloudflare |
| SMB via tunnel | `smb-<name>.hcply.com` — File Sharing through Cloudflare |
| sudo NOPASSWD | One-time password, permanent sudo |
| Keychain auto-unlock | Unlocks on SSH login via `.zshenv` hook |
| Password sync | Every 6h syncs to cloud + `change-password.sh` tool |
| Screen Sharing (VNC) | Port 5900 enabled, stealth mode |
| AppleScript grant | 37 apps granted automation (one-time approval) |
| Keep-apps-alive | Mail + WhatsApp + Messages kept running every 5 min |

## Manager Commands (`~/bin/mac`)

```
mac                    Interactive menu (auto-discovers all Macs + VPS)
mac <name>             SSH via tunnel
mac <name> lan         SSH via LAN
mac status <name>      Check lid/display/lock/idle/active apps
mac screen <name>      VNC with auto-login + auto-unlock lock screen
mac grant <name>       Batch AppleScript permission grant (one-time)
mac update             Self-update from GitHub
```

## How It Works

```
Your Mac                          Remote Mac
────────                          ──────────
mac lucy ──── lucy.hcply.com ───→ SSH (port 22)
mac screen ── vnc-lucy.hcply.com → VNC (port 5900) + CGEvent unlock
mac files ─── smb-lucy.hcply.com → SMB (port 445)
mac grant ─── SSH + osascript ──→ AppleScript automation per app
mac status ── SSH + ioreg ──────→ lid/display/lock/idle detection
```

- **Named tunnel**: Each Mac gets a permanent hostname (e.g., `lucy.hcply.com`) — no random URLs
- **Multi-service**: SSH, VNC, SMB all through the same Cloudflare tunnel
- **Auto-discovery**: CF Worker API tracks all registered Macs with tunnel hostnames, LAN IPs
- **Auto-unlock**: Uses `kCGHIDEventTap` (hardware-level CGEvent) via SSH — bypasses lock screen
- **Self-update**: Background hash check every hour, `mac update` to pull latest

## CF Access Setup (Required for tunnel SSH)

Named tunnels require a Cloudflare Access application for the websocket proxy to work.

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com)
2. Navigate to **Access** > **Applications** > **Add an application**
3. Select **Self-hosted**, set domain to `*.hcply.com`
4. Add **Google** as identity provider
5. Create policy: Allow emails `dmd.fami@gmail.com`
6. For specific machines, add additional allowed emails as needed

## Requirements

- macOS (Apple Silicon or Intel)
- Node.js 18+ (setup installs via Homebrew if missing)
- `cloudflared` (setup installs via Homebrew)
- Cloudflare account with `hcply.com` zone (one-time `cloudflared tunnel login`)
- `pyobjc-framework-Quartz` on manager Mac (for CGEvent screen unlock)
