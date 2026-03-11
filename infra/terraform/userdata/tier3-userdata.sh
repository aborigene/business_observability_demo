#!/bin/bash
# EC2 User Data Script for Tier 3 (C Legacy with Dynatrace OneAgent Infra-Only)

set -e

# Variables - These will be replaced by Terraform templatefile()
DT_ENV_URL="${dt_env_url}"
DT_PAAS_TOKEN="${dt_paas_token}"
TIER4_HOST="${tier4_host}"
TIER4_PORT="${tier4_port}"

echo "=== Starting Tier 3 EC2 Instance Setup ==="
echo "Timestamp: $(date)"

# Update system
echo "Updating system packages..."
yum update -y

# Install required packages
echo "Installing build tools and dependencies..."
yum install -y gcc make wget curl

# Install Dynatrace OneAgent in Infrastructure-Only mode
echo "=== Installing Dynatrace OneAgent (Infrastructure-Only Mode) ==="

# Download OneAgent installer
INSTALLER_URL="$${DT_ENV_URL}/api/v1/deployment/installer/agent/unix/default/latest?flavor=default&arch=x86&bitness=64"

echo "Downloading OneAgent from: $${DT_ENV_URL}"
wget -O /tmp/Dynatrace-OneAgent-Linux.sh \
  --header="Authorization: Api-Token $${DT_PAAS_TOKEN}" \
  "$${INSTALLER_URL}"

# Install OneAgent in infra-only mode
echo "Installing OneAgent in infrastructure-only mode..."
sudo /bin/sh /tmp/Dynatrace-OneAgent-Linux.sh \
  --set-infra-only=true \
  --set-host-property=Tier=tier3 \
  --set-host-property=Environment=demo \
  --set-host-property=Application=loan-risk-engine

# Wait for OneAgent to start
sleep 10

# Configure log collection
echo "=== Configuring Dynatrace Log Collection ==="
mkdir -p /var/lib/dynatrace/oneagent/agent/config/loganalytics

cat > /var/lib/dynatrace/oneagent/agent/config/loganalytics/loan-risk-engine.json << 'EOF'
{
  "logs": [
    {
      "source": {
        "path": "/var/log/loan-risk-engine/app.log"
      },
      "format": {
        "type": "json"
      },
      "attributes": [
        {
          "key": "service.name",
          "value": "tier3-risk-analysis"
        },
        {
          "key": "tier",
          "value": "tier3"
        }
      ]
    }
  ]
}
EOF

# Create log directory
mkdir -p /var/log/loan-risk-engine
chmod 755 /var/log/loan-risk-engine

# Restart OneAgent
echo "Restarting OneAgent..."
systemctl restart oneagent

# Create deployment instructions
cat > /etc/motd << 'EOF'
========================================
Tier 3 - Risk Analysis Engine (C Legacy)
Dynatrace OneAgent: Infrastructure-Only
========================================

Application deployment required.
See GitHub repo for deployment instructions.

Logs: /var/log/loan-risk-engine/app.log
OneAgent: systemctl status oneagent
EOF

echo "=== Tier 3 EC2 Instance Setup Complete ==="
