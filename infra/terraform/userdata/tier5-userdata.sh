#!/bin/bash
# EC2 User Data Script for Tier 5 (.NET 8 with Dynatrace OneAgent Full Stack)

set -e

# Variables - These will be replaced by Terraform templatefile()
DT_ENV_URL="${dt_env_url}"
DT_PAAS_TOKEN="${dt_paas_token}"
DATABASE_URL="${database_url}"
BASE_RATE="${base_rate}"

echo "=== Starting Tier 5 EC2 Instance Setup ==="
echo "Timestamp: $(date)"

# Update system
echo "Updating system packages..."
yum update -y

# Install .NET 8
echo "=== Installing .NET 8 ==="
rpm -Uvh https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
yum install -y dotnet-sdk-8.0

# Verify installation
dotnet --version

# Install Dynatrace OneAgent in Full Stack mode
echo "=== Installing Dynatrace OneAgent (Full Stack Mode) ==="
INSTALLER_URL="$${DT_ENV_URL}/api/v1/deployment/installer/agent/unix/default/latest?flavor=default&arch=x86&bitness=64"

echo "Downloading OneAgent from: $${DT_ENV_URL}"
wget -O /tmp/Dynatrace-OneAgent-Linux.sh \
  --header="Authorization: Api-Token $${DT_PAAS_TOKEN}" \
  "$${INSTALLER_URL}"

# Install OneAgent in full stack mode
echo "Installing OneAgent in full stack mode..."
sudo /bin/sh /tmp/Dynatrace-OneAgent-Linux.sh \
  --set-host-property=Tier=tier5 \
  --set-host-property=Environment=demo \
  --set-host-property=Application=loan-finalizer

# Wait for OneAgent to start
sleep 10

# Create application directory
mkdir -p /opt/loan-finalizer
cd /opt/loan-finalizer

# Set up environment variables
cat > /opt/loan-finalizer/app.env << ENVEOF
ASPNETCORE_URLS=http://+:5000
ASPNETCORE_ENVIRONMENT=Production
DATABASE_URL=$${DATABASE_URL}
Loan__BaseRate=$${BASE_RATE}
ENVEOF

# Create systemd service
cat > /etc/systemd/system/loan-finalizer.service << 'SVCEOF'
[Unit]
Description=Loan Finalizer Service (Tier 5 - .NET 8)
After=network.target oneagent.service

[Service]
Type=notify
User=root
WorkingDirectory=/opt/loan-finalizer
ExecStart=/usr/bin/dotnet /opt/loan-finalizer/LoanFinalizer.dll
Restart=always
RestartSec=5

EnvironmentFile=/opt/loan-finalizer/app.env

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

# Create deployment instructions
cat > /etc/motd << 'EOF'
========================================
Tier 5 - Loan Finalizer (.NET 8)
Dynatrace OneAgent: Full Stack Mode
========================================

Application deployment required.
See GitHub repo for deployment instructions.

Service: loan-finalizer.service
OneAgent: systemctl status oneagent
EOF

echo "=== Tier 5 EC2 Instance Setup Complete ==="
