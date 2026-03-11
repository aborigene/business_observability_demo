#!/bin/bash
# EC2 User Data Script for Tier 3 (C Legacy with Dynatrace OneAgent Infra-Only)

set -e

# Variables - These should be replaced by Terraform
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
INSTALLER_URL="${DT_ENV_URL}/api/v1/deployment/installer/agent/unix/default/latest?flavor=default&arch=x86&bitness=64"

echo "Downloading OneAgent from: ${DT_ENV_URL}"
wget -O /tmp/Dynatrace-OneAgent-Linux.sh \
  --header="Authorization: Api-Token ${DT_PAAS_TOKEN}" \
  "${INSTALLER_URL}"

# Install OneAgent in infra-only mode
echo "Installing OneAgent in infrastructure-only mode..."
sudo /bin/sh /tmp/Dynatrace-OneAgent-Linux.sh \
  --set-infra-only=true \
  --set-host-property=Tier=tier3 \
  --set-host-property=Environment=demo \
  --set-host-property=Application=loan-risk-engine

# Wait for OneAgent to start
sleep 10

# Configure log collection for the application
echo "=== Configuring Dynatrace Log Collection ==="

# Create OneAgent log monitoring configuration
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

# Restart OneAgent to pick up log configuration
echo "Restarting OneAgent to apply log configuration..."
systemctl restart oneagent

# Deploy Tier 3 Application
echo "=== Deploying Tier 3 C Legacy Application ==="

# Copy application files
mkdir -p /opt/tier3-c-legacy
cd /opt/tier3-c-legacy

# In production, you would copy from S3 or artifact repo
# For this script, assuming files are available in /tmp or similar
# Placeholder for actual deployment

# For demo purposes, create a simple download/copy mechanism
# In real scenario, use: aws s3 cp s3://your-bucket/tier3-app.tar.gz .

# Build and install application
# (Assuming source code is deployed via another mechanism)
cat > /opt/tier3-c-legacy/install-app.sh << 'APPINSTALL'
#!/bin/bash
# This script should be run after source code is available
cd /opt/tier3-c-legacy
make clean
make
make install

# Update systemd service with environment variables
cat > /etc/systemd/system/loan-risk-engine.service << SVCEOF
[Unit]
Description=Loan Risk Analysis Engine (Tier 3 - C Legacy)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/loan-risk-engine
ExecStart=/opt/loan-risk-engine/loan-risk-server
Restart=always
RestartSec=5

Environment="TIER4_HOST=${TIER4_HOST}"
Environment="TIER4_PORT=${TIER4_PORT}"

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable loan-risk-engine
systemctl start loan-risk-engine
APPINSTALL

chmod +x /opt/tier3-c-legacy/install-app.sh

# Post-installation message
cat > /etc/motd << 'EOF'
========================================
Tier 3 - Loan Risk Analysis Engine (C Legacy)
Dynatrace OneAgent: Infrastructure-Only Mode
========================================

Application: /opt/loan-risk-engine/loan-risk-server
Logs: /var/log/loan-risk-engine/app.log
Service: loan-risk-engine.service

To complete installation after deploying source code:
  sudo /opt/tier3-c-legacy/install-app.sh

To view application logs:
  tail -f /var/log/loan-risk-engine/app.log

To view service status:
  systemctl status loan-risk-engine

Dynatrace OneAgent Status:
  systemctl status oneagent
EOF

echo "=== Tier 3 EC2 Instance Setup Complete ==="
echo "OneAgent installed in Infrastructure-Only mode"
echo "Log collection configured for /var/log/loan-risk-engine/app.log"
echo "Application deployment script ready at: /opt/tier3-c-legacy/install-app.sh"
