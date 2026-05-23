#!/bin/bash
# ============================================================
# CloudRDP Production Setup Script v4.0
# Proven for Ubuntu 22.04 GitHub Actions Runners
# Uses: Xvnc + LXDE + PAM Bypass + Polkit Fix + Bore Tunnel
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
  tigervnc-standalone-server \
  tigervnc-common \
  tightvncserver \
  lxde \
  lxde-core \
  lxde-common \
  lxsession \
  lxpanel \
  lxterminal \
  pcmanfm \
  dbus-x11 \
  at-spi2-core \
  autocutsel \
  policykit-1 \
  x11-xserver-utils \
  xfonts-base \
  xfonts-75dpi \
  xfonts-100dpi

# ---- [2/5] Configure User & Auth ----
echo "--- [2/5] Configuring User & Authentication ---"

# Use the native 'runner' user (trusted by GHA)
echo "runner:CloudRDP2026!" | sudo chpasswd
sudo usermod -aG sudo,video,ssl-cert,render,xrdp runner 2>/dev/null || true

# FULL PAM Bypass: GHA runners lack systemd-logind.
# Standard PAM crashes the session. We MUST use pam_permit with LXDE!
sudo tee /etc/pam.d/xrdp-sesman > /dev/null << 'PAMEOF'
auth       required   pam_permit.so
account    required   pam_permit.so
session    optional   pam_systemd.so
session    required   pam_permit.so
password   required   pam_permit.so
PAMEOF

# Create XDG_RUNTIME_DIR for runner (required by dbus/polkit/lxsession)
# Without this, the session manager exits immediately with "Failed to connect to socket"
sudo mkdir -p /run/user/1001
sudo chown runner:runner /run/user/1001
sudo chmod 700 /run/user/1001

# ---- [3/5] Configure XRDP & Desktop ----
echo "--- [3/5] Configuring XRDP & Desktop Environment ---"

# Set up LXDE session for the runner user.
# Must use 'exec' so the X session lives as long as lxde-session does.
# Without exec, the .xsession script exits and xrdp terminates the session.
sudo su - runner -c "cat > ~/.xsession << 'XSEOF'
#!/bin/bash
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=LXDE
export DESKTOP_SESSION=LXDE
export XDG_RUNTIME_DIR=/run/user/\$(id -u)
mkdir -p \${XDG_RUNTIME_DIR}
chmod 700 \${XDG_RUNTIME_DIR}
exec dbus-launch --exit-with-session startlxde
XSEOF
chmod +x ~/.xsession"

# Rewrite startwm.sh to isolate the session from GitHub Actions environment variables.
# Key: We set XDG_RUNTIME_DIR before launching so lxsession/dbus can find its socket.
sudo tee /etc/xrdp/startwm.sh > /dev/null << 'SWMEOF'
#!/bin/bash
# Unset GHA-specific variables that pollute the desktop session
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
unset GITHUB_ACTION
unset GITHUB_ACTIONS

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# Set up runtime dir — required for dbus socket and lxsession
export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=LXDE
export DESKTOP_SESSION=LXDE

# Source lxde environment if present
[ -f /etc/X11/Xsession.d/60x11-common_localhost ] && . /etc/X11/Xsession.d/60x11-common_localhost || true

exec startlxde
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

# Fix xrdp.ini: comment out [Xorg], set Xvnc as default, add clean [Xvnc] section
# Using sed + tee (reliable) instead of Python heredoc (can fail silently in GHA)

# 1. Comment out [Xorg] section header AND its contents
sudo sed -i 's/^\[Xorg\]/# [Xorg]/' /etc/xrdp/xrdp.ini
sudo sed -i '/^# \[Xorg\]/,/^\[/{/^\[/!s/^/#X /}' /etc/xrdp/xrdp.ini

# 2. Remove any existing [Xvnc] section so we rewrite it clean
sudo sed -i '/^\[Xvnc\]/,/^\[/{/^\[Xvnc\]/d;/^\[/!d}' /etc/xrdp/xrdp.ini

# 3. Set Xvnc as the default session in [Globals]
sudo sed -i 's/^autorun=.*/autorun=Xvnc/' /etc/xrdp/xrdp.ini || true

# 4. Append a clean, explicit [Xvnc] section at the end
sudo tee -a /etc/xrdp/xrdp.ini > /dev/null << 'XVNCEOF'

[Xvnc]
name=Xvnc
lib=libvnc.so
username=ask
password=ask
ip=127.0.0.1
port=-1
delay_ms=2000
XVNCEOF

# 5. Pre-fill vnc-any to point to local VNC server (port 5900)
sudo sed -i '/^\[vnc-any\]/,/^\[/{s/^ip=.*/ip=127.0.0.1/;s/^port=.*/port=5900/}' /etc/xrdp/xrdp.ini || true

echo "  xrdp.ini sections after fix:"
sudo grep '^\[' /etc/xrdp/xrdp.ini

# ---- [4/5] Start Services ----
echo "--- [4/5] Starting Services ---"

# Start a tightvncserver on display :0 (port 5900) as runner user.
# NOTE: tightvncserver max password length = 8 chars. Use 'CloudRDP' (8 chars).
# If you use 'CloudRDP2026!' it is silently truncated to 'CloudRDP'.
sudo su - runner -c "mkdir -p ~/.vnc"

# Set VNC password using printf | vncpasswd -f (non-interactive, works on all versions)
printf 'CloudRDP\nCloudRDP\n' | sudo su - runner -c "vncpasswd" 2>/dev/null || \
  printf 'CloudRDP' | sudo su - runner -c "vncpasswd -f > ~/.vnc/passwd && chmod 600 ~/.vnc/passwd" 2>/dev/null || true

# Kill any stale VNC servers first
sudo su - runner -c "tightvncserver -kill :0 2>/dev/null; tightvncserver -kill :1 2>/dev/null" 2>/dev/null || true
sleep 1

# Write LXDE startup BEFORE starting VNC (so it's used on first launch)
sudo su - runner -c "cat > ~/.vnc/xstartup << 'VNCEOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR=/run/user/\$(id -u)
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=LXDE
export DESKTOP_SESSION=LXDE
mkdir -p \${XDG_RUNTIME_DIR}
chmod 700 \${XDG_RUNTIME_DIR}
exec dbus-launch --exit-with-session startlxde
VNCEOF
chmod +x ~/.vnc/xstartup"

# Run tightvncserver as a systemd service so GHA process killer doesn't terminate it
sudo tee /etc/systemd/system/vncserver.service > /dev/null << 'VNCSERVICEEOF'
[Unit]
Description=TightVNC Server
After=network.target

[Service]
Type=forking
User=runner
Group=runner
WorkingDirectory=/home/runner
Environment=USER=runner
Environment=XDG_RUNTIME_DIR=/run/user/1001
ExecStartPre=-/usr/bin/tightvncserver -kill :0
ExecStart=/usr/bin/tightvncserver :0 -geometry 1280x800 -depth 24 -dpi 96
ExecStop=/usr/bin/tightvncserver -kill :0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
VNCSERVICEEOF

sudo systemctl daemon-reload
sudo systemctl enable --now vncserver.service
sleep 3

VNC_STATUS=$(sudo systemctl is-active vncserver.service || echo 'not started')
echo "  VNC Service Status — ${VNC_STATUS}"
echo "  VNC Password: CloudRDP  (8 chars, tightvncserver limit)"

# Start XRDP services
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

# Make the XDG_RUNTIME_DIR persistent across the session lifecycle
# This is a systemd tmpfiles rule so the dir is always present
echo 'd /run/user/1001 0700 runner runner -' | sudo tee /etc/tmpfiles.d/runner-runtime.conf > /dev/null
sudo systemd-tmpfiles --create /etc/tmpfiles.d/runner-runtime.conf 2>/dev/null || true

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
