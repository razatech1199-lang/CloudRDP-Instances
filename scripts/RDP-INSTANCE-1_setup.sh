#!/bin/bash
# ============================================================
# CloudRDP Production Setup Script v5.0
# Proven for Ubuntu 22.04 GitHub Actions Runners
# Uses: TightVNC (display :1) + LXDE + PAM Bypass + Bore Tunnel
# ============================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Start background log streamer to send system logs to the backend
if [ -n "${BACKEND_URL:-}" ] && [ -n "${INSTANCE_ID:-}" ]; then
  cat << 'LOGEOF' > /tmp/log_streamer.sh
#!/bin/bash
export BACKEND_URL="$1"
export INSTANCE_ID="$2"

send_log() {
  local msg="$1"
  local json_payload
  if command -v jq &>/dev/null; then
    json_payload=$(jq -n --arg msg "$msg" '{message: $msg}')
  else
    # Simple shell-based JSON string escaping fallback
    local escaped
    escaped=$(echo -n "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g')
    json_payload="{\"message\": \"$escaped\"}"
  fi
  curl -s -k -X POST "${BACKEND_URL}/instance/${INSTANCE_ID}/log" \
    -H "Content-Type: application/json" \
    -d "$json_payload" &>/dev/null || true
}

send_log "[LOGGER] 📡 Remote log streamer started on GHA runner."
send_log "[DIAG] 🔧 User: $(whoami), UID: $(id -u)"
send_log "[DIAG] 🔧 Hostname: $(hostname)"

# Dump systemd journals for troubleshooting
send_log "[DIAG] 🔧 vncserver journal:"
journalctl -u vncserver --no-pager -n 40 2>&1 | while read -r line; do
  send_log "[VNC-JOURNAL] $line"
done

send_log "[DIAG] 🔧 xrdp journal:"
journalctl -u xrdp --no-pager -n 40 2>&1 | while read -r line; do
  send_log "[XRDP-JOURNAL] $line"
done

# Monitor xrdp logs
touch /var/log/xrdp.log /var/log/xrdp-sesman.log 2>/dev/null || true
chown runner /var/log/xrdp.log /var/log/xrdp-sesman.log 2>/dev/null || true

tail -n 0 -F /var/log/xrdp.log 2>/dev/null | while read -r line; do
  send_log "[XRDP] $line"
done &

tail -n 0 -F /var/log/xrdp-sesman.log 2>/dev/null | while read -r line; do
  send_log "[SESMAN] $line"
done &

# Check for VNC server logs
for i in {1..20}; do
  vnc_log=$(ls /home/runner/.vnc/*.log 2>/dev/null | head -n 1)
  if [ -n "$vnc_log" ]; then
    send_log "[LOGGER] 📂 Found VNC log at $vnc_log, starting stream..."
    tail -n 0 -F "$vnc_log" 2>/dev/null | while read -r line; do
      send_log "[VNC] $line"
    done &
    break
  fi
  sleep 2
done

# Periodically report services status
while true; do
  sleep 15
  send_log "[STATUS] Port 5901: $(ss -tlnp 2>/dev/null | grep 5901 || echo 'CLOSED'), Port 3389: $(ss -tlnp 2>/dev/null | grep 3389 || echo 'CLOSED')"
  send_log "[STATUS] Services: vnc=$(systemctl is-active vncserver 2>/dev/null || echo 'inactive'), xrdp=$(systemctl is-active xrdp 2>/dev/null || echo 'inactive')"
done
LOGEOF
  chmod +x /tmp/log_streamer.sh
  /tmp/log_streamer.sh "$BACKEND_URL" "$INSTANCE_ID" >/dev/null 2>&1 &
fi

echo "============================================"
echo "  CloudRDP Setup v5.0 — Starting..."
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

echo "runner:CloudRDP2026!" | sudo chpasswd
sudo usermod -aG sudo,video,ssl-cert,render,xrdp runner 2>/dev/null || true

# FULL PAM Bypass — GHA runners lack systemd-logind
sudo tee /etc/pam.d/xrdp-sesman > /dev/null << 'PAMEOF'
auth       required   pam_permit.so
account    required   pam_permit.so
session    optional   pam_systemd.so
session    required   pam_permit.so
password   required   pam_permit.so
PAMEOF

# XDG_RUNTIME_DIR for runner (required by dbus/polkit/lxsession)
sudo mkdir -p /run/user/1001
sudo chown runner:runner /run/user/1001
sudo chmod 700 /run/user/1001

# ---- [3/5] Configure XRDP & Desktop ----
echo "--- [3/5] Configuring XRDP & Desktop Environment ---"

# Set up LXDE xsession for the runner user
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

# Rewrite startwm.sh — clean GHA env variables before launching desktop
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
unset GITHUB_ACTION
unset GITHUB_ACTIONS

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=LXDE
export DESKTOP_SESSION=LXDE

[ -f /etc/X11/Xsession.d/60x11-common_localhost ] && . /etc/X11/Xsession.d/60x11-common_localhost || true

exec startlxde
SWMEOF
sudo chmod +x /etc/xrdp/startwm.sh

# Idle/disconnect settings
sudo sed -i 's/^IdleTimeLimit=.*/IdleTimeLimit=0/' /etc/xrdp/sesman.ini || echo 'IdleTimeLimit=0' >> /etc/xrdp/sesman.ini
sudo sed -i 's/^KillDisconnected=.*/KillDisconnected=false/' /etc/xrdp/sesman.ini || echo 'KillDisconnected=false' >> /etc/xrdp/sesman.ini

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

# Add xrdp user to ssl-cert group so it can read keys
sudo usermod -aG ssl-cert xrdp 2>/dev/null || true

# Generate TLS certs for xrdp
if [ ! -f /etc/xrdp/cert.pem ]; then
  sudo openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem \
    -days 365 -subj "/CN=CloudRDP" 2>/dev/null
fi
sudo chown root:ssl-cert /etc/xrdp/cert.pem /etc/xrdp/key.pem || true
sudo chmod 640 /etc/xrdp/key.pem || true
sudo chmod 644 /etc/xrdp/cert.pem || true

# Optimize XRDP settings for negotiate security (fixes Windows 11 RC4 deprecation hang)
sudo sed -i 's/^security_layer=.*/security_layer=negotiate/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^crypt_level=.*/crypt_level=high/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^max_bpp=.*/max_bpp=24/g' /etc/xrdp/xrdp.ini

# -------------------------------------------------------
# Write a CLEAN xrdp.ini — no fragile sed chain-patching.
# We comment out [Xorg] and [Xvnc] sections from the stock
# config and append a clean [Xvnc] block pointing to
# display :1 (port 5901).
# -------------------------------------------------------

# Comment out all default session sections in the stock xrdp.ini to avoid confusion/fallback
sudo sed -i 's/^\[Xorg\]/# \[Xorg\]/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^\[Xvnc\]/# \[Xvnc\]/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^\[vnc-any\]/# \[vnc-any\]/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^\[neutrinordp-any\]/# \[neutrinordp-any\]/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^\[xrdp/# \[xrdp/g' /etc/xrdp/xrdp.ini 2>/dev/null || true

# Set Xvnc as the auto-run session in [Globals]
sudo sed -i 's/^autorun=.*/autorun=Xvnc/' /etc/xrdp/xrdp.ini || true

# Append a clean, explicit [Xvnc] block pointing to port 5901 (display :1)
# Using username=runner and password=CloudRDP to allow seamless auto-login bypass.
sudo tee -a /etc/xrdp/xrdp.ini > /dev/null << 'XVNCEOF'

[Xvnc]
name=Xvnc
lib=libvnc.so
username=runner
password=CloudRDP
ip=127.0.0.1
port=5901
delay_ms=2000
XVNCEOF

echo "  xrdp.ini active sections:"
sudo grep '^\[' /etc/xrdp/xrdp.ini

# ---- [4/5] Start VNC & XRDP Services ----
echo "--- [4/5] Starting VNC & XRDP Services ---"

# Prepare VNC password (max 8 chars for tightvncserver)
sudo -u runner mkdir -p /home/runner/.vnc
echo 'CloudRDP' | vncpasswd -f > /home/runner/.vnc/passwd
chown runner:runner /home/runner/.vnc/passwd
chmod 600 /home/runner/.vnc/passwd

# Kill any stale VNC servers
sudo su - runner -c "tightvncserver -kill :1 2>/dev/null; tightvncserver -kill :0 2>/dev/null" 2>/dev/null || true
sleep 1

# Remove stale lock files for display :1
sudo rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

# Write LXDE VNC startup script BEFORE starting VNC
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

# Run tightvncserver as a systemd service on display :1 (port 5901)
sudo tee /etc/systemd/system/vncserver.service > /dev/null << 'VNCSERVICEEOF'
[Unit]
Description=TightVNC Server (display :1)
After=network.target

[Service]
Type=forking
User=runner
Group=runner
WorkingDirectory=/home/runner
Environment=USER=runner
Environment=HOME=/home/runner
Environment=XDG_RUNTIME_DIR=/run/user/1001
ExecStartPre=-/usr/bin/tightvncserver -kill :1
ExecStart=/usr/bin/tightvncserver :1 -geometry 1280x800 -depth 24 -dpi 96
ExecStop=/usr/bin/tightvncserver -kill :1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
VNCSERVICEEOF

sudo systemctl daemon-reload
sudo systemctl enable --now vncserver.service
sleep 4

# Verify VNC started on port 5901
VNC_STATUS=$(sudo systemctl is-active vncserver.service || echo 'not started')
echo "  VNC Service Status: ${VNC_STATUS}"
if [ "${VNC_STATUS}" != "active" ]; then
  echo "  [ERROR] VNC service failed to start. Logs:"
  sudo journalctl -u vncserver.service --no-pager -n 30 || true
  echo "  Attempting direct start..."
  sudo rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
  sudo su - runner -c "tightvncserver :1 -geometry 1280x800 -depth 24 -dpi 96" || true
  sleep 3
fi

# Verify port 5901 is listening
ss -tlnp | grep 5901 && echo "  Port 5901 is OPEN — VNC OK" || echo "  [WARNING] Port 5901 not detected"

# Start XRDP
sudo systemctl enable xrdp
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman
sleep 3

echo "  XRDP Status:   $(systemctl is-active xrdp)"
echo "  Sesman Status: $(systemctl is-active xrdp-sesman)"

# Disable power management & screensaver
sudo apt-get remove -y xfce4-power-manager xscreensaver light-locker 2>/dev/null || true

# Persist XDG_RUNTIME_DIR via tmpfiles
echo 'd /run/user/1001 0700 runner runner -' | sudo tee /etc/tmpfiles.d/runner-runtime.conf > /dev/null
sudo systemd-tmpfiles --create /etc/tmpfiles.d/runner-runtime.conf 2>/dev/null || true

# ---- [5/5] Start Tmate Tunnel & Report ----
echo "--- [5/5] Starting Tmate Tunnel ---"

# Install tmate if not present
if ! command -v tmate &> /dev/null; then
  sudo apt-get update -qy
  sudo apt-get install -y tmate
fi

# Start tmate in a detached session
tmate -S /tmp/tmate.sock new-session -d

# Retrieve the SSH connection string
TUNNEL_URL=""
for i in $(seq 1 15); do
  SSH_CONN=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}' 2>/dev/null || echo "")
  if [ -n "$SSH_CONN" ] && [[ "$SSH_CONN" == ssh* ]]; then
    # Extract only the username@host (remove the 'ssh ' prefix)
    TUNNEL_URL=$(echo "$SSH_CONN" | sed 's/^ssh //')
    break
  fi
  sleep 2
done

if [ -n "$TUNNEL_URL" ]; then
    echo "============================================"
    echo "  ✅ Tmate Tunnel Active: $TUNNEL_URL"
    echo "  👤 Username: runner"
    echo "  🔑 Password: CloudRDP2026!"
    echo "============================================"

    # Write to GitHub Actions summary
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        echo "### 🚀 CloudRDP Instance Ready" >> $GITHUB_STEP_SUMMARY
        echo "**Tunnel Address:** \`$TUNNEL_URL\`" >> $GITHUB_STEP_SUMMARY
        echo "**Username:** \`runner\`" >> $GITHUB_STEP_SUMMARY
        echo "**Password:** \`CloudRDP2026!\`" >> $GITHUB_STEP_SUMMARY
    fi

    # Report tunnel address to backend
    for attempt in $(seq 1 5); do
        HTTP_CODE=$(curl -sSL -k -o /dev/null -w "%{http_code}" \
            -X POST "${BACKEND_URL}/instance/${INSTANCE_ID}/report" \
            -H "Content-Type: application/json" \
            -H "Bypass-Tunnel-Reminder: true" \
            -d "{\"ip_address\": \"${TUNNEL_URL}\"}" 2>/dev/null || echo "000")
        echo "  Report attempt $attempt: HTTP $HTTP_CODE"
        [ "$HTTP_CODE" = "200" ] && break
        sleep 3
    done

    echo "CloudRDP: Setup Complete. Waiting for connections..."
else
    echo "❌ Tmate tunnel failed to start."
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        echo "### ❌ Tmate Tunnel Failed to Start" >> $GITHUB_STEP_SUMMARY
        echo "Check the GitHub Actions logs for details." >> $GITHUB_STEP_SUMMARY
    fi
fi
