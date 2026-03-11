#!/bin/bash
set -e

echo "=== Tier 3: C Legacy Application Installation Script ==="

# Install build tools if not present
echo "Installing build dependencies..."
yum install -y gcc make || apt-get install -y gcc make

# Build the application
echo "Building C application..."
cd /tmp/tier3-c-legacy || cd /opt/tier3-c-legacy
make clean
make

# Install the binary
echo "Installing binary..."
sudo make install

# Install systemd service
echo "Installing systemd service..."
sudo cp loan-risk-engine.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable loan-risk-engine
sudo systemctl start loan-risk-engine

echo "=== Installation Complete ==="
echo "Service status:"
sudo systemctl status loan-risk-engine --no-pager
echo ""
echo "Logs location: /var/log/loan-risk-engine/app.log"
echo "To view logs: tail -f /var/log/loan-risk-engine/app.log"
