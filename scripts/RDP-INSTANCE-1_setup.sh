#!/bin/bash

# CloudRDP Absolute Minimalist Setup Script
# Restoring the exact universally proven method for GitHub Actions without hacks.

export DEBIAN_FRONTEND=noninteractive

echo "--- [1/3] Installing Dependencies ---"
sudo apt-get update -qy
# REMOVED --no-install-recommends to ensure background services (like snakeoil cert generators) run properly
sudo apt-get install -y xrdp xfce4 xfce4-goodies tmate

echo "--- [2/3] Configuring Session ---"
USER_HOME=$(eval echo "~$(whoami)")
echo "xfce4-session" > $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession
chown $(whoami):$(whoami) $USER_HOME/.xsession

# Proven patch: Replace startwm.sh with a robust version that handles DBUS correctly
sudo mv /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.bak
cat << 'EOF' | sudo tee /etc/xrdp/startwm.sh > /dev/null
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_TYPE=x11
exec dbus-run-session -- startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

# Force XRDP to listen on IPv4 to avoid localhost resolution issues with tmate
sudo sed -i 's/^port=3389/port=tcp:\/\/0.0.0.0:3389/' /etc/xrdp/xrdp.ini

# Fix Xorg permissions for non-root users
sudo sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config || echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config > /dev/null

echo "--- [3/3] Setting Credentials & Restarting ---"
CURRENT_USER=$(whoami)
echo "$CURRENT_USER:CloudRDP2026!" | sudo chpasswd
echo "root:CloudRDP2026!" | sudo chpasswd

# Disable TLS completely to avoid OpenSSL 3.0 hangs on Ubuntu 22.04
# The connection is already secured by the SSH tunnel
sudo sed -i 's/^.*security_layer=.*/security_layer=rdp/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^.*crypt_level=.*/crypt_level=high/' /etc/xrdp/xrdp.ini

sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "CloudRDP: Minimal Setup Complete."
