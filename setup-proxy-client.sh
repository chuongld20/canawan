#!/bin/bash

set -e  # Exit immediately if any command fails

echo "✅ Detecting server public IP..."
PUBLIC_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
echo "   → Detected IP: $PUBLIC_IP"

echo "🔹 Updating system and installing unzip..."
sudo apt update && sudo apt install -y unzip wget

# Create installation directory
INSTALL_DIR="/config/proxy-service/client"
mkdir -p "$INSTALL_DIR"

echo "🔹 Downloading proxy client..."
wget -O /tmp/BigCat.Proxy.Client.zip "https://dev-proxy-api.canawan.com/proxy/BigCat.Proxy.Client.zip"

echo "🔹 Extracting files..."
unzip -o /tmp/BigCat.Proxy.Client.zip -d "$INSTALL_DIR"
rm /tmp/BigCat.Proxy.Client.zip

echo "Granting execute permission to BigCat.Proxy.Client in $INSTALL_DIR"
chmod +x "$INSTALL_DIR/BigCat.Proxy.Client"

echo "🔹 Creating systemd service..."
SERVICE_FILE="/etc/systemd/system/proxy-client.service"
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Proxy Client Service
After=network.target

[Service]
Environment="LD_LIBRARY_PATH=/config/proxy-service/client"
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/BigCat.Proxy.Client \
    --defaultServerEndPointIP=$PUBLIC_IP \
    --portAPI=9000 \
    --passwordAPI=66778899 \
    --defaultPortIPv4=9010 \
    --maxConnections=-1 \
    --maxConnectionPerCredential=-1 \
    --networkInterface=ens6 \
    --ipV6RotationSeconds=-1 \
    --fromPort=20000 \
    --toPort=30000 \
    --autoOffAllFirewall=true \
    --autoConfigPortFirewall=false \
    --showFullDebug=false
Restart=always
StandardOutput=append:/var/log/proxy-client.log
StandardError=append:/var/log/proxy-client-error.log

[Install]
WantedBy=multi-user.target
EOF

echo "🔹 Enabling and starting service..."
sudo systemctl daemon-reload
sudo systemctl enable --now proxy-client

echo "✅ Installation complete! Check service status with:"
echo "   sudo systemctl status proxy-client"
echo "   journalctl -u proxy-client -f"
