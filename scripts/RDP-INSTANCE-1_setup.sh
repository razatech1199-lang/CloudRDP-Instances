#!/bin/bash
# ============================================================
# CloudRDP Production Setup Script v3.0
# Proven for Ubuntu 22.04 GitHub Actions Runners
# Uses: Xvfb + XFCE4 + PAM Bypass + Polkit Fix + Bore Tunnel
# ============================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "============================================"
echo "  CloudRDP Setup v3.0 — Starting..."
echo "============================================"

# ---- [1/5] Install Dependencies ----
echo "--- [1/5] Installing Core Dependencies ---"
sudo apt-get update -qy
sudo apt-get install -y \
  xrdp \
  xfce4 xfce4-goodies \
  dbus-x11 \
  xvfb \
  autocutsel \
  policykit-1 \
  x11-xserver-utils

# ---- [2/5] Configure User & Auth ----
echo "--- [2/5] Configuring User & Authentication ---"

# Use the native 'runner' user (trusted by GHA)
echo "runner:1Pakistan@143" | sudo chpasswd
sudo usermod -aG sudo,video,ssl-cert,render,xrdp runner 2>/dev/null || true

# Bypass PAM for XRDP — proven to work on GHA runners
sudo tee /etc/pam.d/xrdp-sesman > /dev/null << 'PAMEOF'
auth       required   pam_permit.so
account    required   pam_permit.so
session    required   pam_permit.so
password   required   pam_permit.so
PAMEOF

# ---- [3/5] Configure XRDP & Desktop ----
echo "--- [3/5] Configuring XRDP & Desktop Environment ---"

# Rewrite startwm.sh for reliable XFCE startup
sudo tee /etc/xrdp/startwm.sh > /dev/null << 'SWMEOF'
#!/bin/sh
# CloudRDP startwm.sh — Clean XFCE launch
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# Start clipboard sync daemon
autocutsel -fork 2>/dev/null &
autocutsel -selection PRIMARY -fork 2>/dev/null &

# Launch XFCE with dbus
exec dbus-launch --exit-with-session startxfce4
SWMEOF
sudo chmod +x /etc/xrdp/startwm.sh

# Create .xsession for runner
sudo tee /home/runner/.xsession > /dev/null << 'XSEOF'
#!/bin/bash
# CloudRDP .xsession
autocutsel -fork 2>/dev/null &
autocutsel -selection PRIMARY -fork 2>/dev/null &
xrdp-chansrv 2>/dev/null &
exec dbus-launch --exit-with-session startxfce4
XSEOF
sudo chown runner:runner /home/runner/.xsession
chmod +x /home/runner/.xsession

# Polkit fix — prevent "Color Manager" authentication hang
sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla > /dev/null << 'PKEOF'
[Allow Colord for all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
PKEOF

# Allow non-console X sessions (headless fix)
sudo sed -i 's/allowed_users=console/allowed_users=anybody/g' /etc/X11/Xwrapper.config 2>/dev/null || true

# Optimize XRDP settings for tunneled connections
sudo sed -i 's/^security_layer=.*/security_layer=rdp/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^crypt_level=.*/crypt_level=low/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^max_bpp=.*/max_bpp=24/g' /etc/xrdp/xrdp.ini

# Generate fresh TLS certs for xrdp
if [ ! -f /etc/xrdp/cert.pem ]; then
  sudo openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem \
    -days 365 -subj "/CN=CloudRDP" 2>/dev/null
fi

# ---- [4/5] Start Services ----
echo "--- [4/5] Starting Services ---"

# Start Xvfb virtual framebuffer on display :10
Xvfb :10 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
export DISPLAY=:10
sleep 2

sudo systemctl enable xrdp
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman
sleep 3

# Verify
echo "  XRDP Status:   $(systemctl is-active xrdp)"
echo "  Sesman Status: $(systemctl is-active xrdp-sesman)"
grep "AllowRootLogin" /etc/xrdp/sesman.ini || true

# ---- [5/5] Start Tunnel & Report ----
echo "--- [5/5] Starting Bore Tunnel ---"

wget -q https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
tar -xf bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
chmod +x bore

nohup ./bore local 3389 --to bore.pub > bore.log 2>&1 &
BORE_PID=$!
sleep 5

TUNNEL_URL=""
for i in $(seq 1 15); do
    TUNNEL_URL=$(grep -oE "bore.pub:[0-9]+" bore.log | head -n 1)
    [ ! -z "$TUNNEL_URL" ] && break
    sleep 2
done

if [ ! -z "$TUNNEL_URL" ]; then
    echo "============================================"
    echo "  ✅ Tunnel Active: $TUNNEL_URL"
    echo "  👤 Username: runner"
    echo "  🔑 Password: 1Pakistan@143"
    echo "============================================"

    # Report tunnel address to backend
    for attempt in $(seq 1 3); do
        HTTP_CODE=$(curl -sSL -k -o /dev/null -w "%{http_code}" \
            -X POST "${BACKEND_URL}/instance/${INSTANCE_ID}/report" \
            -H "Content-Type: application/json" \
            -H "Bypass-Tunnel-Reminder: true" \
            -d "{\"ip_address\": \"${TUNNEL_URL}\"}" 2>/dev/null || echo "000")
        [ "$HTTP_CODE" = "200" ] && break
        sleep 3
    done

    echo "CloudRDP: Setup Complete. Waiting for connections..."
else
    echo "❌ Bore tunnel failed to start."
    echo "--- Bore Log ---"
    cat bore.log 2>/dev/null || echo "(empty)"
    echo "--- End Log ---"
fi
