#!/bin/bash

# CloudRDP "Safe Mode" Setup Script
# Using VNC backend for maximum reliability on headless runners.

export DEBIAN_FRONTEND=noninteractive

echo "--- [1/3] Installing Dependencies ---"
sudo apt-get update -qy
sudo apt-get install -y xrdp xfce4 xfce4-goodies tightvncserver dbus-x11 tmate

echo "--- [2/3] Configuring Safe Mode Session ---"
USER_HOME=$(eval echo "~$(whoami)")
echo "xfce4-session" > $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession
chown $(whoami):$(whoami) $USER_HOME/.xsession

# Configure XRDP to use VNC by default (more stable than Xorg on GHA)
sudo sed -i 's/WaitTime=2/WaitTime=30/g' /etc/xrdp/sesman.ini
sudo sed -i 's/^security_layer=.*/security_layer=rdp/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^crypt_level=.*/crypt_level=low/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^max_bpp=.*/max_bpp=24/g' /etc/xrdp/xrdp.ini

# Ensure startwm.sh is minimalist
sudo mv /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.bak
cat << 'EOF' | sudo tee /etc/xrdp/startwm.sh > /dev/null
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

# Force Xvnc as the first priority in xrdp.ini
sudo sed -i '0,/\[Xorg\]/s/\[Xorg\]/\[Xvnc\]/' /etc/xrdp/xrdp.ini
sudo sed -i '0,/libxup.so/s/libxup.so/libvnc.so/' /etc/xrdp/xrdp.ini

echo "--- [3/3] Finalizing ---"
# Create a dedicated RDP user
sudo useradd -m -s /bin/bash cloudrdp
echo "cloudrdp:1Pakistan@143" | sudo chpasswd
sudo usermod -aG sudo,video,ssl-cert,render cloudrdp

# Fix X11 permissions for headless runners
sudo sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config || echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config
echo "needs_root_rights=no" | sudo tee -a /etc/X11/Xwrapper.config

# Setup session for the new user
echo "startxfce4" | sudo tee /home/cloudrdp/.xsession
sudo chown cloudrdp:cloudrdp /home/cloudrdp/.xsession

sudo systemctl enable xrdp
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "--- [4/4] Starting Tunnel & Reporting ---"
# Download Bore
wget -q https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
tar -xf bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
chmod +x bore

# Start tunnel
nohup ./bore local 3389 --to bore.pub > bore.log 2>&1 &
sleep 5

# Get URL
for i in {1..10}; do
    TUNNEL_URL=$(grep -oE "bore.pub:[0-9]+" bore.log | head -n 1)
    [ ! -z "$TUNNEL_URL" ] && break
    sleep 2
done

if [ ! -z "$TUNNEL_URL" ]; then
    echo "Tunnel Established: $TUNNEL_URL"
    # Report IP to backend
    curl -s -X POST "$BACKEND_URL/instance/$INSTANCE_ID/report" \
        -H "Content-Type: application/json" \
        -H "Bypass-Tunnel-Reminder: true" \
        -d "{\"ip_address\": \"$TUNNEL_URL\"}"
fi

echo "CloudRDP: Safe Mode Setup Complete."
