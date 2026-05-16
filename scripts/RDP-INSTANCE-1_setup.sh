echo "--- [1/3] Installing Core GUI Components ---"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qy
sudo apt-get install -y xrdp xfce4 xfce4-goodies dbus-x11 xvfb

echo "--- [2/3] Configuring RDP Environment ---"
# Create RDP user
sudo useradd -m -s /bin/bash cloudrdp
echo "cloudrdp:1Pakistan@143" | sudo chpasswd
sudo usermod -aG sudo,video,ssl-cert,render,xrdp cloudrdp
sudo usermod -aG ssl-cert xrdp

# Fix X11 permissions
sudo sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config || echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config
echo "needs_root_rights=no" | sudo tee -a /etc/X11/Xwrapper.config

# Optimize xrdp for maximum stability
sudo sed -i 's/^security_layer=.*/security_layer=rdp/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^crypt_level=.*/crypt_level=low/g' /etc/xrdp/xrdp.ini

# Setup desktop session (Golden start sequence)
cat << 'EOF' | sudo tee /home/cloudrdp/.xsession > /dev/null
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec dbus-launch --exit-with-session startxfce4
EOF
sudo chmod +x /home/cloudrdp/.xsession
sudo chown cloudrdp:cloudrdp /home/cloudrdp/.xsession

echo "--- [3/3] Finalizing Services ---"
sudo systemctl enable xrdp
sudo systemctl restart xrdp

echo "--- [4/4] Starting Tunnel ---"
wget -q https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
tar -xf bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
chmod +x bore

nohup ./bore local 3389 --to bore.pub > bore.log 2>&1 &
sleep 5

for i in {1..10}; do
    TUNNEL_URL=$(grep -oE "bore.pub:[0-9]+" bore.log | head -n 1)
    [ ! -z "$TUNNEL_URL" ] && break
    sleep 2
done

if [ ! -z "$TUNNEL_URL" ]; then
    echo "Tunnel Established: $TUNNEL_URL"
    curl -s -X POST "$BACKEND_URL/instance/$INSTANCE_ID/report" \
        -H "Content-Type: application/json" \
        -H "Bypass-Tunnel-Reminder: true" \
        -d "{\"ip_address\": \"$TUNNEL_URL\"}"
fi

echo "CloudRDP: Setup Complete."
