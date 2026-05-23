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
  xorgxrdp \
  xserver-xorg-legacy \
  tightvncserver \
  lxde-core \
  lxterminal \
  dbus-x11 \
  autocutsel \
  policykit-1 \
  x11-xserver-utils

# ---- [2/5] Configure User & Auth ----
echo "--- [2/5] Configuring User & Authentication ---"

# Use the native 'runner' user (trusted by GHA)
echo "runner:CloudRDP2026!" | sudo chpasswd
sudo usermod -aG sudo,video,ssl-cert,render,xrdp runner 2>/dev/null || true

# FULL PAM Bypass: GHA runners lack systemd-logind.
# Standard PAM crashes the session, and XFCE4 hangs. We MUST use pam_permit and LXDE!
sudo tee /etc/pam.d/xrdp-sesman > /dev/null << 'PAMEOF'
auth       required   pam_permit.so
account    required   pam_permit.so
session    required   pam_permit.so
password   required   pam_permit.so
PAMEOF

# ---- [3/5] Configure XRDP & Desktop ----
echo "--- [3/5] Configuring XRDP & Desktop Environment ---"

# Install tightvncserver for software rendering (bypasses hardware DRM crashes)
sudo apt-get install -y tightvncserver

# Set up LXDE for the runner user
sudo su - runner -c "echo 'startlxde' > ~/.xsession"

# Rewrite startwm.sh to isolate the session from GitHub Actions environment variables.
# We explicitly unset polluting vars instead of 'env -i' which strips too much (causing blank screens).
sudo tee /etc/xrdp/startwm.sh > /dev/null << 'SWMEOF'
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
unset SESSION_MANAGER
unset GITHUB_ENV
unset GITHUB_PATH
unset GITHUB_WORKSPACE
unset GITHUB_STEP_SUMMARY
unset GITHUB_STATE
unset GITHUB_OUTPUT
unset RUNNER_TRACKING_ID

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=LXDE
export DESKTOP_SESSION=LXDE

exec dbus-launch --exit-with-session startlxde
SWMEOF
sudo chmod +x /etc/xrdp/startwm.sh
# Configure XRDP idle timeout to never disconnect
sudo sed -i 's/^IdleTimeLimit=.*/IdleTimeLimit=0/' /etc/xrdp/sesman.ini || echo 'IdleTimeLimit=0' >> /etc/xrdp/sesman.ini
sudo sed -i 's/^KillDisconnected=.*/KillDisconnected=false/' /etc/xrdp/sesman.ini || echo 'KillDisconnected=false' >> /etc/xrdp/sesman.ini
sudo systemctl restart xrdp

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
sudo mkdir -p /etc/X11
echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config > /dev/null

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

# XRDP services will be started
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

# Disable power management & screensaver to prevent sleep disconnects
sudo apt-get remove -y xfce4-power-manager xscreensaver light-locker 2>/dev/null || true

wget -q https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
tar -xf bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
sudo mv bore /usr/local/bin/
sudo chmod +x /usr/local/bin/bore

# Run bore as a systemd service so GHA doesn't kill it when the step ends
sudo tee /etc/systemd/system/bore.service > /dev/null << 'BOREEOF'
[Unit]
Description=Bore Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/bore local 3389 --to bore.pub
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
BOREEOF

sudo systemctl daemon-reload
sudo systemctl enable --now bore.service
sleep 5

TUNNEL_URL=""
for i in $(seq 1 15); do
    TUNNEL_URL=$(sudo journalctl -u bore.service -n 50 | grep -oE "bore.pub:[0-9]+" | head -n 1)
    [ ! -z "$TUNNEL_URL" ] && break
    sleep 2
done

if [ ! -z "$TUNNEL_URL" ]; then
    echo "============================================"
    echo "  ✅ Tunnel Active: $TUNNEL_URL"
    echo "  👤 Username: runner"
    echo "  🔑 Password: CloudRDP2026!"
    echo "============================================"

    # Fallback: Write directly to GitHub Actions UI
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        echo "### 🚀 CloudRDP Instance Ready" >> $GITHUB_STEP_SUMMARY
        echo "**Tunnel Address:** \`$TUNNEL_URL\`" >> $GITHUB_STEP_SUMMARY
        echo "**Username:** \`runner\`" >> $GITHUB_STEP_SUMMARY
        echo "**Password:** \`CloudRDP2026!\`" >> $GITHUB_STEP_SUMMARY
    fi

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
    sudo journalctl -u bore.service --no-pager -n 20 2>/dev/null || echo "(empty)"
    echo "--- End Log ---"
    
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        echo "### ❌ Tunnel Failed to Start" >> $GITHUB_STEP_SUMMARY
        echo "Check the GitHub Actions logs for details." >> $GITHUB_STEP_SUMMARY
    fi
fi
