#!/bin/bash

# Function to print characters with delay
print_with_delay() {
    text="$1"
    delay="$2"
    for ((i = 0; i < ${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

# Introduction animation
echo ""
echo ""
print_with_delay "hysteria-installer by Imoagh" 0.1
echo ""
echo ""

# Check for and install required packages
install_required_packages() {
    REQUIRED_PACKAGES=("curl" "jq" "openssl")
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            apt-get update > /dev/null 2>&1
            apt-get install -y $pkg > /dev/null 2>&1
        fi
    done
}

# Check if the directory /root/hysteria already exists
if [ -d "/root/hysteriav1" ]; then
    echo "Hysteria seems to be already installed."
    echo ""
    echo "Choose an option:"
    echo ""
    echo "1) Reinstall"
    echo ""
    echo "2) Modify"
    echo ""
    echo "3) Uninstall"
    echo ""
    read -p "Enter your choice: " choice
    case $choice in
        1)
            # Reinstall
            rm -rf /root/hysteriav1
            systemctl stop hysteriav1
            pkill -f hysteria-linux-amd64
            systemctl disable hysteriav1 > /dev/null 2>&1
            rm /etc/systemd/system/hysteriav1.service
            ;;
        2)
            
            # Modify
            cd /root/hysteriav1

            # Get current values
            current_port=$(jq -r '.listen' config.json | cut -d':' -f2)
            current_password=$(jq -r '.obfs' config.json)
            echo ""
            read -p "Enter a new port (or press enter to keep the current one [$current_port]): " new_port
            echo ""
            [ -z "$new_port" ] && new_port=$current_port
            echo ""
            read -p "Enter a new password (or press enter to keep the current one [$current_password]): " new_password
            echo ""
            [ -z "$new_password" ] && new_password=$current_password
            echo ""
            read -p "Enable recv_window_conn and recv_window? (y/n, default is n): " new_recv_window_enable
            echo ""
            if [ -z "$new_recv_window_enable" ] || [ "$new_recv_window_enable" != "y" ]; then
                new_recv_window_enable="n"
            fi

            # Modify the config.json using jq based on the user's input
            jq ".listen = \":$new_port\"" config.json > temp.json && mv temp.json config.json
            jq ".obfs = \"$new_password\"" config.json > temp.json && mv temp.json config.json

            if [ "$new_recv_window_enable" == "n" ]; then
                jq 'del(.recv_window_conn, .recv_window)' config.json > temp.json && mv temp.json config.json
            else
                jq '.recv_window_conn = 3407872 | .recv_window = 13631488' config.json > temp.json && mv temp.json config.json
            fi
            systemctl daemon-reload
            systemctl restart hysteriav1
            # Print client configs
            PUBLIC_IP=$(curl -s https://api.ipify.org)
            read -p "Enter your upload speed (Mbps): " up_mbps
            echo ""
            read -p "Enter your download speed (Mbps): " down_mbps
            v2rayN_config='{
              "server": "'$PUBLIC_IP:$new_port'",
              "obfs": "'$new_password'",
              "protocol": "udp",
              "up_mbps": '$up_mbps',
              "down_mbps": '$down_mbps',
              "insecure": true,
              "socks5": {
                "listen": "127.0.0.1:10808"
              },
              "http": {
                "listen": "127.0.0.1:10809"
              },
              "disable_mtu_discovery": true,
              "resolver": "https://223.5.5.5/dns-query"
            }'
            if [ "$new_recv_window_enable" == "y" ]; then
                v2rayN_config=$(echo "$v2rayN_config" | jq '. + {"recv_window_conn": 3407872, "recv_window": 13631488}')
            fi

            echo "v2rayN client config:"
            echo "$v2rayN_config" | jq .
            echo

            nekobox_url="hysteria://$PUBLIC_IP:$new_port/?insecure=1&upmbps=$up_mbps&downmbps=$down_mbps&obfs=xplus&obfsParam=$new_password"
            echo "NekoBox/NekoRay URL:"
            echo ""
            echo "$nekobox_url"
            echo ""
            exit 0
            ;;
        3)
            # Uninstall
            rm -rf /root/hysteriav1
            systemctl stop hysteriav1
            pkill -f hysteria-linux-amd64
            systemctl disable hysteriav1 > /dev/null 2>&1
            rm /etc/systemd/system/hysteriav1.service
            echo "Hysteria v1 uninstalled successfully!"
            echo ""
            exit 0
            ;;
        *)
            echo "Invalid choice."
            exit 1
            ;;
    esac
fi

# Install required packages if not already installed
install_required_packages
# Step 1: Check OS and architecture
OS="$(uname -s)"
ARCH="$(uname -m)"

# Determine binary name
BINARY_NAME=""
case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64) BINARY_NAME="hysteria-linux-amd64";;
      # Add more architectures if needed
      *) echo "Unsupported architecture"; exit 1;;
    esac;;
  # Add more OS checks if needed
  *) echo "Unsupported OS"; exit 1;;
esac

# Step 2: Download the binary
mkdir -p /root/hysteriav1
cd /root/hysteriav1
wget -q "https://github.com/apernet/hysteria/releases/download/v1.3.5/hysteria-linux-amd64"
chmod 755 hysteria-linux-amd64

# Step 3: Create self-signed certs
openssl ecparam -genkey -name prime256v1 -out ca.key
openssl req -new -x509 -days 36500 -key ca.key -out ca.crt -subj "/CN=bing.com"

# Step 4: Prompt user for input
echo ""
read -p "Enter a port (or press enter for a random port): " port
echo ""
if [ -z "$port" ]; then
  port=$((RANDOM + 10000))
fi
echo ""
read -p "Enter a password (or press enter for a random password): " password
echo ""
if [ -z "$password" ]; then
  password=$(tr -dc 'a-zA-Z0-9-@#$%^&+=_' < /dev/urandom | fold -w 8 | head -n 1)
fi

echo ""
read -p "Enable recv_window_conn and recv_window? (y/n): " recv_window_enable
echo ""
config_json='{
  "listen": ":'$port'",
  "cert": "/root/hysteriav1/ca.crt",
  "key": "/root/hysteriav1/ca.key",
  "obfs": "'$password'",
  "disable_mtu_discovery": true,
  "resolver": "https://223.5.5.5/dns-query"
}'
if [ "$recv_window_enable" == "y" ]; then
  config_json=$(echo "$config_json" | jq '. + {"recv_window_conn": 3407872, "recv_window": 13631488}')
fi
echo "$config_json" > config.json

# Step 5: Run the binary and check the log
./hysteria-linux-amd64 server > hysteria.log &
sleep 2
if grep -q "Server up and running" hysteria.log; then
  echo ""
  echo "Server started successfully."
  echo ""
else
  echo ""
  echo "Error installing, check log file."
  echo ""
  exit 1
fi

# Step 6: Create a system service
cat > /etc/systemd/system/hysteriav1.service <<EOL
[Unit]
Description=Hysteria VPN Service
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root/hysteriav1
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/root/hysteriav1/hysteria-linux-amd64 server
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOL



systemctl daemon-reload
systemctl enable hysteriav1 > /dev/null 2>&1
systemctl start hysteriav1
systemctl restart hysteriav1

# Step 7: Generate and print two client config files
PUBLIC_IP=$(curl -s https://api.ipify.org)
read -p "Enter your upload speed (Mbps): " up_mbps
echo ""
read -p "Enter your download speed (Mbps): " down_mbps
echo ""
v2rayN_config='{
  "server": "'$PUBLIC_IP:$port'",
  "obfs": "'$password'",
  "protocol": "udp",
  "up_mbps": '$up_mbps',
  "down_mbps": '$down_mbps',
  "insecure": true,
  "socks5": {
    "listen": "127.0.0.1:10808"
  },
  "http": {
    "listen": "127.0.0.1:10809"
  },
  "disable_mtu_discovery": true,
  "resolver": "https://223.5.5.5/dns-query"
}'
if [ "$recv_window_enable" == "y" ]; then
  v2rayN_config=$(echo "$v2rayN_config" | jq '. + {"recv_window_conn": 3407872, "recv_window": 13631488}')
fi
echo "v2rayN client config:"
echo ""
echo "$v2rayN_config"
echo ""
nekobox_url="hysteria://$PUBLIC_IP:$port/?insecure=1&upmbps=$up_mbps&downmbps=$down_mbps&obfs=xplus&obfsParam=$password"
echo ""
echo "NekoBox/NekoRay URL:"
echo ""
echo "$nekobox_url"
echo ""
