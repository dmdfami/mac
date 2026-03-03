# dmdfami/mac

One-command full remote control for any Mac. SSH + VNC + AppleScript automation — no SIP modification needed.

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
| Cloudflare Tunnel | LaunchDaemon — runs without login, auto-restart on reboot |
| Auto-register | Tunnel URL registered to CF Worker API on every start |
| sudo NOPASSWD | One-time password, permanent sudo |
| Keychain auto-unlock | Unlocks on SSH login via `.zshenv` hook |
| Password sync | Every 6h syncs to cloud + `change-password.sh` tool |
| Screen Sharing (VNC) | Port 5900 enabled |
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
mac lucy ──── CF Tunnel ────────→ SSH (port 22)
mac screen ── SSH tunnel 5901 ──→ VNC (port 5900) + CGEvent unlock
mac grant ─── SSH + osascript ──→ AppleScript automation per app
mac status ── SSH + ioreg ──────→ lid/display/lock/idle detection
```

- **Auto-discovery**: CF Worker API tracks all registered Macs with tunnel URLs, LAN IPs
- **Auto-unlock**: Uses `kCGHIDEventTap` (hardware-level CGEvent) via SSH — bypasses lock screen
- **Self-update**: Background hash check every hour, `mac update` to pull latest

## Requirements

- macOS (Apple Silicon or Intel)
- Node.js 18+ (setup installs via Homebrew if missing)
- `cloudflared` (setup installs via Homebrew)
- `pyobjc-framework-Quartz` on manager Mac (for CGEvent screen unlock)
