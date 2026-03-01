#!/bin/bash
# ============================================
# DAVID'S MAC REMOTE — Idempotent (chạy bao nhiêu lần cũng OK)
# ============================================
clear
echo "=========================================="
echo "  Mac Remote Setup"
echo "=========================================="

API="https://mac-nodes.dmd-fami.workers.dev"
KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFi38QEU6BlyGvfozRqZh9VKynr51NwUMjUHMOdmM5Gj export@vietnam-plywood.com"
CF="/opt/homebrew/bin/cloudflared"

# 1. Homebrew (skip if exists)
if command -v brew &>/dev/null; then
  echo "[1/6] Homebrew OK (skip)"
else
  echo "[1/6] Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 2. Node.js (skip if exists)
if command -v node &>/dev/null; then
  echo "[2/6] Node.js OK (skip)"
else
  echo "[2/6] Installing Node.js..."
  brew install node 2>/dev/null
fi

# 3. SSH + key (idempotent — grep trước khi thêm)
echo "[3/6] SSH + key..."
sudo systemsetup -setremotelogin on 2>/dev/null
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qF "$KEY" ~/.ssh/authorized_keys 2>/dev/null || echo "$KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 4. Cloudflared (skip if exists)
if [ -f "$CF" ]; then
  echo "[4/6] cloudflared OK (skip)"
else
  echo "[4/6] Installing cloudflared..."
  brew install cloudflared 2>/dev/null
fi

# 5. Tunnel wrapper + LaunchAgent (overwrite = update)
echo "[5/6] Tunnel service..."
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

mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.cloudflare.tunnel.plist << 'PEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cloudflare.tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>tunnel-wrapper.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/USERPLACEHOLDER</string>
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
sed -i '' "s|USERPLACEHOLDER|$(whoami)|" ~/Library/LaunchAgents/com.cloudflare.tunnel.plist

# Restart tunnel service
launchctl unload ~/Library/LaunchAgents/com.cloudflare.tunnel.plist 2>/dev/null
pkill -f "cloudflared tunnel" 2>/dev/null
sleep 1
launchctl load ~/Library/LaunchAgents/com.cloudflare.tunnel.plist

# 6. Claude CLI keychain unlock hint
# 6. Claude CLI keychain unlock
# 6. Claude CLI — unlock keychain for SSH access
echo "[6/6] Claude CLI..."
if command -v claude &>/dev/null; then
  echo "      Enter your Mac login password to unlock keychain:"
  read -s -p "      Password: " KPASS
  echo ""
  security unlock-keychain -p "$KPASS" ~/Library/Keychains/login.keychain-db 2>/dev/null && echo "      Keychain unlocked!" || echo "      Wrong password (skip)"
  unset KPASS
else
  echo "      Claude CLI not installed (skip)"
fi

# Wait for tunnel
echo ""
echo "Waiting for tunnel..."
TUNNEL_URL=""
for i in {1..20}; do
  TUNNEL_URL=$(grep -o 'https://[a-z0-9\-]*\.trycloudflare\.com' /tmp/cf-tunnel.log 2>/dev/null | tail -1)
  if [ -n "$TUNNEL_URL" ]; then break; fi
  sleep 3
done

MY_USER=$(whoami)
MY_LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
MY_HOST=$(scutil --get ComputerName 2>/dev/null || hostname)

echo ""
echo "============================================"
echo "  DONE!"
echo "  Tunnel: ${TUNNEL_URL:-check /tmp/cf-tunnel.log}"
echo "  LAN:    ssh $MY_USER@$MY_LAN"
echo "  Host:   $MY_HOST"
echo "  Reboot: auto-reconnect YES"
echo "============================================"
read -p "Press Enter to close..."
