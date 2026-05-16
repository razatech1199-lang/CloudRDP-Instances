echo "--- [1/3] Installing GUI, VNC & Clipboard Helpers ---"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qy
sudo apt-get install -y xrdp xfce4 xfce4-goodies tightvncserver dbus-x11 autocutsel

echo "--- [2/3] Configuring Native Runner User ---"
# Set password for the native 'runner' user
echo "runner:1Pakistan@143" | sudo chpasswd
sudo usermod -aG sudo,video,ssl-cert,render,xrdp runner

# Setup desktop session for 'runner'
USER_HOME="/home/runner"
cat << 'EOF' | sudo tee $USER_HOME/.xsession > /dev/null
#!/bin/bash
autocutsel -fork
xrdp-chansrv &
exec dbus-launch --exit-with-session startxfce4
EOF
sudo chown runner:runner $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession

# Ensure XRDP can read the session
sudo cp $USER_HOME/.xsession /etc/skel/.xsession

# Restore default PAM (it works better for the native user)
sudo apt-get install -y --reinstall xrdp

echo "--- [3/3] Finalizing Services ---"
sudo systemctl enable xrdp
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

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
