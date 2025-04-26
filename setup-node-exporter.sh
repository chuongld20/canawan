#!/bin/bash

# Function to install Node Exporter on the client
install_node_exporter() {
  echo "Starting the installation of Node Exporter on the client..."

  # Step 1: Download Node Exporter
  echo "Downloading Node Exporter..."
  cd /tmp
  wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to download Node Exporter. Exiting."
    exit 1
  fi

  # Step 2: Extract and install Node Exporter
  echo "Extracting Node Exporter..."
  tar -xvzf node_exporter-1.6.1.linux-amd64.tar.gz
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to extract Node Exporter. Exiting."
    exit 1
  fi
  sudo mv node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to move Node Exporter to /usr/local/bin/. Exiting."
    exit 1
  fi

  # Step 3: Create Node Exporter systemd service
  echo "Creating systemd service for Node Exporter..."
  echo "
  [Unit]
  Description=Prometheus Node Exporter
  After=network.target

  [Service]
  ExecStart=/usr/local/bin/node_exporter

  [Install]
  WantedBy=multi-user.target
  " | sudo tee /etc/systemd/system/node_exporter.service

  # Step 4: Reload systemd and enable Node Exporter service
  echo "Reloading systemd and enabling Node Exporter service..."
  sudo systemctl daemon-reload
  sudo systemctl enable node_exporter
  sudo systemctl start node_exporter
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to start Node Exporter service. Exiting."
    exit 1
  fi

  # Step 5: Check Node Exporter status
  echo "Node Exporter service status:"
  sudo systemctl status node_exporter --no-pager

  echo "Node Exporter installation completed successfully!"
}

# Function to open port 9100 for Node Exporter
open_node_exporter_port() {
  echo "Opening port 9100 for Node Exporter..."

  # Use ufw (Uncomplicated Firewall) to allow traffic on port 9100
  sudo ufw allow 9100/tcp
  sudo ufw reload
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to open port 9100. Exiting."
    exit 1
  fi

  # Check ufw status
  sudo ufw status
}

# Main execution
echo "Starting installation of Node Exporter and firewall configuration..."
install_node_exporter
open_node_exporter_port

echo "Node Exporter setup is complete. Please ensure that Prometheus is configured to scrape the Node Exporter target."
