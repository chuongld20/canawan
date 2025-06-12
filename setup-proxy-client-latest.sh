#!/bin/bash
set -e  # Exit immediately if any command fails

# Check required environment variables
check_required_vars() {
    local missing_vars=()
    
    if [ -z "$NETWORK_INTERFACE" ]; then
        missing_vars+=("NETWORK_INTERFACE")
    fi
    
    if [ -z "$PORT_API" ]; then
        missing_vars+=("PORT_API")
    fi
    
    if [ -z "$PORT_IPV4" ]; then
        missing_vars+=("PORT_IPV4")
    fi
    
    if [ -z "$FROM_PORT" ]; then
        missing_vars+=("FROM_PORT")
    fi
    
    if [ -z "$TO_PORT" ]; then
        missing_vars+=("TO_PORT")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "❌ Error: Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "   - $var"
        done
        echo ""
        echo "Usage: Set the following environment variables before running this script:"
        echo "   export NETWORK_INTERFACE=ens6"
        echo "   export PORT_API=9000"
        echo "   export PORT_IPV4=9010"
        echo "   export FROM_PORT=20000"
        echo "   export TO_PORT=50000"
        echo ""
        echo "Then run: curl -sSL https://your-script-url.sh | bash"
        exit 1
    fi
}

# Check required variables
check_required_vars

# Get configuration from environment variables (required)
NETWORK_INTERFACE_CONFIG="$NETWORK_INTERFACE"
PORT_API_CONFIG="$PORT_API"
PORT_IPV4_CONFIG="$PORT_IPV4"
FROM_PORT_CONFIG="$FROM_PORT"
TO_PORT_CONFIG="$TO_PORT"

echo "🔧 Using configuration:"
echo "   Network Interface: $NETWORK_INTERFACE_CONFIG"
echo "   API Port: $PORT_API_CONFIG"
echo "   IPv4 Port: $PORT_IPV4_CONFIG"
echo "   Port Range: $FROM_PORT_CONFIG-$TO_PORT_CONFIG"

grep -qxF "root soft nofile 65535" /etc/security/limits.conf || echo "root soft nofile 65535" | sudo tee -a /etc/security/limits.conf
grep -qxF "root hard nofile 65535" /etc/security/limits.conf || echo "root hard nofile 65535" | sudo tee -a /etc/security/limits.conf

su - root

ulimit -n

echo "✅ Detecting server public IP..."
PUBLIC_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
echo "   → Detected IP: $PUBLIC_IP"

if systemctl list-unit-files | grep -q "proxy-client.service"; then
    if systemctl is-active --quiet proxy-client; then
        systemctl stop proxy-client
        echo "Stopped service proxy-client."
    else
        echo "Service proxy-client not running."
    fi
else
    echo "Service proxy-client not found"
fi

echo "🔹 Updating system and installing unzip..."
sudo apt install -y unzip wget

# Create installation directory
INSTALL_DIR="/config/proxy-service/client"
mkdir -p "$INSTALL_DIR"

echo "--- Clear folder"
rm -rf $INSTALL_DIR/*

echo "🔹 Downloading proxy client..."
wget -O /tmp/BigCat.Proxy.ClientV2.zip "https://dev-proxy-api.canawan.com/proxy/BigCat.Proxy.ClientV2.zip?$(date +%s)"

echo "🔹 Extracting files..."
unzip -o /tmp/BigCat.Proxy.ClientV2.zip -d "$INSTALL_DIR"
rm /tmp/BigCat.Proxy.ClientV2.zip

echo "Granting execute permission to $INSTALL_DIR/BigCat.Proxy.ClientV2"
sudo chmod +x "$INSTALL_DIR/BigCat.Proxy.Client"

echo "🔹 Stopping and removing old proxy-client service if exists..."
sudo systemctl stop proxy-client 2>/dev/null || true
sudo systemctl disable proxy-client 2>/dev/null || true

timeout 10 pkill -9 -f BigCat.Proxy.Client || echo "⚠️ Process not found or timeout reached."
# sudo ip -6 addr flush dev $NETWORK_INTERFACE_CONFIG
# sleep 5
# sudo ip link set $NETWORK_INTERFACE_CONFIG down
# echo "down $NETWORK_INTERFACE_CONFIG"
# sleep 5
# sudo ip link set $NETWORK_INTERFACE_CONFIG up
# echo "apply"
# sleep 5 
# netplan apply

echo "🔹 Configuring UFW firewall with custom ports..."
ufw allow $PORT_API_CONFIG
ufw allow $PORT_IPV4_CONFIG
ufw allow $FROM_PORT_CONFIG:$TO_PORT_CONFIG/tcp
echo "   → Allowed ports: $PORT_API_CONFIG, $PORT_IPV4_CONFIG, $FROM_PORT_CONFIG:$TO_PORT_CONFIG/tcp"

echo "🔹 Creating new systemd service..."
SERVICE_FILE="/etc/systemd/system/proxy-client.service"
sudo rm -f $SERVICE_FILE

cd $INSTALL_DIR

sudo tee "/config/proxy-service/start_proxy_v2.sh" > /dev/null <<EOL
#!/bin/bash

LOG_FILE="/var/log/proxy-client.log"
LOG_FILE_CHECK="/var/log/proxy-client-check.log"

WORK_DIR=\${1:-"/config/proxy-service/client"}
DEFAULT_IP=\${2:-"192.168.1.100"}
PORT_API=\${3:-$PORT_API_CONFIG}
PASSWORD_API=\${4:-"66778899"}
PORT_IPV4=\${5:-$PORT_IPV4_CONFIG}
NETWORK_INTERFACE=\${6:-"$NETWORK_INTERFACE_CONFIG"}
FROM_PORT=\${7:-$FROM_PORT_CONFIG}
TO_PORT=\${8:-$TO_PORT_CONFIG}

API_URL="http://\$DEFAULT_IP:\$PORT_API/apiProxy/list"

echo "\$(date '+%Y-%m-%d %H:%M:%S') - Starting BigCat.Proxy.Client..." | tee -a "\$LOG_FILE_CHECK"

cd "\$WORK_DIR" || exit 1

./BigCat.Proxy.Hades \\
    --defaultServerEndPointIP="\$DEFAULT_IP" \\
    --portAPI="\$PORT_API" \\
    --passwordAPI="\$PASSWORD_API" \\
    --defaultPortIPv4="\$PORT_IPV4" \\
    --networkInterface="\$NETWORK_INTERFACE" \\
    --fromPort="\$FROM_PORT" \\
    --toPort="\$TO_PORT" \\
    --limitPerProcess=500 \\
    --autoClearLog=true \\
    --fromInternalPort=\$((FROM_PORT - 1000)) \\
    --optimizeIPv6=false \\
    --showFullDebug=false \\
    >> "\$LOG_FILE" 2>&1
EOL

sudo chmod +x /config/proxy-service/start_proxy_v2.sh

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Proxy Client Service
After=network.target

[Service]
ExecStart=/config/proxy-service/start_proxy_v2.sh $INSTALL_DIR $PUBLIC_IP
Restart=on-failure
User=root
WorkingDirectory=/config/proxy-service/client
StandardOutput=append:/var/log/proxy-client.log
StandardError=append:/var/log/proxy-client-error.log
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 $SERVICE_FILE

echo "🔹 Reloading systemd..."
sudo systemctl daemon-reload

echo "🔹 Setting execute permissions..."
sudo chmod g+wx /config/proxy-service/client/BigCat.Proxy.Client
sudo chmod g+wx /config/proxy-service/client/BigCat.Proxy.Hades

echo "🔹 Enabling and starting service..."
sudo systemctl enable proxy-client.service
sudo systemctl start proxy-client.service

echo "✅ Installation complete! Check service status with:"
echo "   sudo systemctl status proxy-client"
echo "   journalctl -u proxy-client -f"
echo ""
echo "🔧 Configuration used:"
echo "   Network Interface: $NETWORK_INTERFACE_CONFIG"
echo "   API Port: $PORT_API_CONFIG"
echo "   IPv4 Port: $PORT_IPV4_CONFIG"
echo "   Port Range: $FROM_PORT_CONFIG-$TO_PORT_CONFIG"
