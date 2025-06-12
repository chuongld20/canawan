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
        echo "   export TRUST_PROXY=http://user:pass@proxy:port  # Optional, for DNS resolution issues"
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

# Function to perform HTTP requests with DNS fallback
perform_request_with_fallback() {
    local url="$1"
    local output_file="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "🌐 Attempt $((retry_count + 1))/$max_retries: Requesting $url"
        
        if [ -n "$output_file" ]; then
            # Download to file
            if wget -O "$output_file" "$url" 2>/dev/null; then
                echo "✅ Successfully downloaded via direct connection"
                return 0
            fi
            
            # Check if it's a DNS-related error by trying to resolve the hostname
            local hostname=$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')
            if ! nslookup "$hostname" >/dev/null 2>&1; then
                echo "⚠️ DNS resolution failed for $hostname, trying with trust proxy..."
                
                # Method 1: Try with environment variables (most compatible)
                if env http_proxy="$TRUST_PROXY" https_proxy="$TRUST_PROXY" wget -O "$output_file" "$url" 2>/dev/null; then
                    echo "✅ Successfully downloaded via trust proxy (env vars)"
                    return 0
                fi
                
                # Method 2: Try with wget -e options
                if wget -e use_proxy=yes -e http_proxy="$TRUST_PROXY" -e https_proxy="$TRUST_PROXY" -O "$output_file" "$url" 2>/dev/null; then
                    echo "✅ Successfully downloaded via trust proxy (wget -e)"
                    return 0
                fi
                
                # Method 3: Try with curl as fallback
                if command -v curl >/dev/null 2>&1; then
                    if curl -L --proxy "$TRUST_PROXY" -o "$output_file" "$url" 2>/dev/null; then
                        echo "✅ Successfully downloaded via trust proxy (curl fallback)"
                        return 0
                    fi
                fi
            else
                echo "⚠️ Network error (not DNS related), retrying..."
            fi
        else
            # Get content (for IP detection)
            local result
            result=$(curl -s4 "$url" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                echo "$result"
                return 0
            fi
            
            # Check if it's a DNS-related error
            local hostname=$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')
            if ! nslookup "$hostname" >/dev/null 2>&1; then
                echo "⚠️ DNS resolution failed for $hostname, trying with trust proxy..."
                
                # Get content with proxy
                local result
                result=$(curl -s4 --proxy "$TRUST_PROXY" "$url" 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$result" ]; then
                    echo "$result"
                    return 0
                fi
            else
                echo "⚠️ Network error (not DNS related), retrying..."
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "⏳ Waiting 3 seconds before retry..."
            sleep 3
        fi
    done
    
    echo "❌ All attempts failed for: $url"
    return 1
}

# Set default TRUST_PROXY if not provided
TRUST_PROXY=${TRUST_PROXY:-"http://ud6Mx7pY:GmuwPQxRG4wR@104.167.228.92:20298"}

# Debug: Show all environment variables for troubleshooting
echo "🐛 Environment variables debug:"
echo "   NETWORK_INTERFACE='$NETWORK_INTERFACE'"
echo "   PORT_API='$PORT_API'"
echo "   PORT_IPV4='$PORT_IPV4'"
echo "   FROM_PORT='$FROM_PORT'"
echo "   TO_PORT='$TO_PORT'"
echo "   TRUST_PROXY='$TRUST_PROXY'"

grep -qxF "root soft nofile 65535" /etc/security/limits.conf || echo "root soft nofile 65535" | sudo tee -a /etc/security/limits.conf
grep -qxF "root hard nofile 65535" /etc/security/limits.conf || echo "root hard nofile 65535" | sudo tee -a /etc/security/limits.conf

# Set ulimit without switching user (which would lose environment variables)
ulimit -n 65535 2>/dev/null || echo "⚠️ Could not set ulimit, continuing..."

echo "✅ Detecting server public IP..."
PUBLIC_IP=$(perform_request_with_fallback "https://ifconfig.me")
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(perform_request_with_fallback "https://icanhazip.com")
fi
if [ -z "$PUBLIC_IP" ]; then
    echo "❌ Failed to detect public IP address"
    exit 1
fi
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
if ! perform_request_with_fallback "https://dev-proxy-api.canawan.com/proxy/BigCat.Proxy.ClientV2.zip?$(date +%s)" "/tmp/BigCat.Proxy.ClientV2.zip"; then
    echo "❌ Failed to download proxy client after all attempts"
    exit 1
fi

echo "🔹 Extracting files..."
unzip -o /tmp/BigCat.Proxy.ClientV2.zip -d "$INSTALL_DIR"
rm /tmp/BigCat.Proxy.ClientV2.zip

echo "Granting execute permission to $INSTALL_DIR/BigCat.Proxy.ClientV2"
sudo chmod +x "$INSTALL_DIR/BigCat.Proxy.Client"

echo "🔹 Stopping and removing old proxy-client service if exists..."
sudo systemctl stop proxy-client 2>/dev/null || true
sudo systemctl disable proxy-client 2>/dev/null || true

timeout 120 pkill -9 -f BigCat.Proxy.Client || echo "⚠️ Process not found or timeout reached."
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

# Create the start script with direct variable substitution
echo "🔹 Creating start script with configuration..."
cat > "/config/proxy-service/start_proxy_v2.sh" << 'START_SCRIPT_EOF'
#!/bin/bash

LOG_FILE="/var/log/proxy-client.log"
LOG_FILE_CHECK="/var/log/proxy-client-check.log"

WORK_DIR=${1:-"/config/proxy-service/client"}
DEFAULT_IP=${2:-"192.168.1.100"}
PORT_API=${3:-PLACEHOLDER_PORT_API}
PASSWORD_API=${4:-"66778899"}
PORT_IPV4=${5:-PLACEHOLDER_PORT_IPV4}
NETWORK_INTERFACE=${6:-"PLACEHOLDER_NETWORK_INTERFACE"}
FROM_PORT=${7:-PLACEHOLDER_FROM_PORT}
TO_PORT=${8:-PLACEHOLDER_TO_PORT}

API_URL="http://$DEFAULT_IP:$PORT_API/apiProxy/list"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting BigCat.Proxy.Client..." | tee -a "$LOG_FILE_CHECK"

cd "$WORK_DIR" || exit 1

./BigCat.Proxy.Hades \
    --defaultServerEndPointIP="$DEFAULT_IP" \
    --portAPI="$PORT_API" \
    --passwordAPI="$PASSWORD_API" \
    --defaultPortIPv4="$PORT_IPV4" \
    --networkInterface="$NETWORK_INTERFACE" \
    --fromPort="$FROM_PORT" \
    --toPort="$TO_PORT" \
    --limitPerProcess=500 \
    --autoClearLog=true \
    --fromInternalPort=$((FROM_PORT - 1000)) \
    --optimizeIPv6=false \
    --showFullDebug=false \
    >> "$LOG_FILE" 2>&1
START_SCRIPT_EOF

# Replace placeholders with actual values
sed -i "s/PLACEHOLDER_PORT_API/$PORT_API_CONFIG/g" /config/proxy-service/start_proxy_v2.sh
sed -i "s/PLACEHOLDER_PORT_IPV4/$PORT_IPV4_CONFIG/g" /config/proxy-service/start_proxy_v2.sh
sed -i "s/PLACEHOLDER_NETWORK_INTERFACE/$NETWORK_INTERFACE_CONFIG/g" /config/proxy-service/start_proxy_v2.sh
sed -i "s/PLACEHOLDER_FROM_PORT/$FROM_PORT_CONFIG/g" /config/proxy-service/start_proxy_v2.sh
sed -i "s/PLACEHOLDER_TO_PORT/$TO_PORT_CONFIG/g" /config/proxy-service/start_proxy_v2.sh

sudo chmod +x /config/proxy-service/start_proxy_v2.sh

echo "🔹 Verifying start script configuration..."
echo "   Script contents:"
head -20 /config/proxy-service/start_proxy_v2.sh | grep -E "(PORT_API|PORT_IPV4|NETWORK_INTERFACE|FROM_PORT|TO_PORT)="

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
