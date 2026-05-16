#!/bin/bash

# CloudRDP Ultimate Stability Script
# Engineered for Ubuntu 22.04 GitHub Actions Runners.

export DEBIAN_FRONTEND=noninteractive

echo "--- [1/3] Installing Dependencies ---"
sudo apt-get update -qy
sudo apt-get install -y xrdp xorgxrdp xfce4 xfce4-goodies dbus-x11 tmate

echo "--- [2/3] Hardening Configuration ---"
# Add current user to ssl-cert group to avoid permission issues with XRDP certificates
sudo adduser $(whoami) ssl-cert

# Configure XFCE Session
USER_HOME=$(eval echo "~$(whoami)")
echo "xfce4-session" > $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession
chown $(whoami):$(whoami) $USER_HOME/.xsession

# Prevent gnome-keyring and other services from hanging the session
mkdir -p $USER_HOME/.config/autostart
echo "[Desktop Entry]
Type=Application
Name=Disable Keyring
Exec=true
Hidden=true" > $USER_HOME/.config/autostart/gnome-keyring-ssh.desktop

# Fix Polkit for colord
sudo mkdir -p /etc/polkit-1/localauthority/50-local.d/
sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

# Robust startwm.sh
sudo mv /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.bak
cat << 'EOF' | sudo tee /etc/xrdp/startwm.sh > /dev/null
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_TYPE=x11

exec dbus-run-session -- startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

# Optimize xrdp.ini & sesman.ini for headless runners
# Increase timeout to 60 seconds to allow XFCE more time to start
sudo sed -i 's/WaitTime=2/WaitTime=60/g' /etc/xrdp/sesman.ini
sudo sed -i 's/^security_layer=.*/security_layer=rdp/g' /etc/xrdp/xrdp.ini || echo "security_layer=rdp" | sudo tee -a /etc/xrdp/xrdp.ini
sudo sed -i 's/^crypt_level=.*/crypt_level=high/g' /etc/xrdp/xrdp.ini || echo "crypt_level=high" | sudo tee -a /etc/xrdp/xrdp.ini

# Ensure Xorg is allowed
sudo sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config || echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config > /dev/null

echo "--- [3/3] Finalizing Credentials ---"
CURRENT_USER=$(whoami)
echo "$CURRENT_USER:CloudRDP2026!" | sudo chpasswd
echo "root:CloudRDP2026!" | sudo chpasswd

# Restart services
sudo systemctl enable xrdp
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "CloudRDP: Setup Complete. Ready for connection."
