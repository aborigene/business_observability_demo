#!/bin/bash
# EC2 User Data Script for Tier 5 (.NET 8 with Dynatrace OneAgent Full Stack)

set -e

# Variables - These should be replaced by Terraform
DT_ENV_URL="${dt_env_url}"
DT_PAAS_TOKEN="${dt_paas_token}"
DATABASE_URL="${database_url}"
BASE_RATE="${base_rate}"

echo "=== Starting Tier 5 EC2 Instance Setup ==="
echo "Timestamp: $(date)"

# Update system
echo "Updating system packages..."
yum update -y

# Install .NET 8 SDK and Runtime
echo "=== Installing .NET 8 ==="
rpm -Uvh https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
yum install -y dotnet-sdk-8.0

# Verify installation
dotnet --version

# Install Dynatrace OneAgent in Full Stack mode
echo "=== Installing Dynatrace OneAgent (Full Stack Mode) ==="

# Download OneAgent installer
INSTALLER_URL="${DT_ENV_URL}/api/v1/deployment/installer/agent/unix/default/latest?flavor=default&arch=x86&bitness=64"

echo "Downloading OneAgent from: ${DT_ENV_URL}"
wget -O /tmp/Dynatrace-OneAgent-Linux.sh \
  --header="Authorization: Api-Token ${DT_PAAS_TOKEN}" \
  "${INSTALLER_URL}"

# Install OneAgent in FULL STACK mode (default)
echo "Installing OneAgent in full stack mode..."
sudo /bin/sh /tmp/Dynatrace-OneAgent-Linux.sh \
  --set-host-property=Tier=tier5 \
  --set-host-property=Environment=demo \
  --set-host-property=Application=loan-finalizer

# Wait for OneAgent to start
sleep 10

echo "OneAgent installation complete. Status:"
systemctl status oneagent --no-pager || true

# Deploy Tier 5 Application
echo "=== Deploying Tier 5 .NET Application ==="

# Create application directory
mkdir -p /opt/loan-finalizer
cd /opt/loan-finalizer

# Set up environment variables
cat > /opt/loan-finalizer/app.env << ENVEOF
ASPNETCORE_URLS=http://+:5000
ASPNETCORE_ENVIRONMENT=Production
DATABASE_URL=${DATABASE_URL}
Loan__BaseRate=${BASE_RATE}
ENVEOF

# Create systemd service
cat > /etc/systemd/system/loan-finalizer.service << SVCEOF
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

# Load environment variables
EnvironmentFile=/opt/loan-finalizer/app.env

# Dynatrace OneAgent will automatically inject itself

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

# Create deployment script for later use
cat > /opt/loan-finalizer/deploy-app.sh << 'DEPLOYEOF'
#!/bin/bash
# This script should be run after the application files are deployed

set -e

echo "Deploying Tier 5 application..."

# Assuming app files are in /tmp/tier5-dotnet or similar
if [ -d "/tmp/tier5-dotnet" ]; then
    cd /tmp/tier5-dotnet
    
    # Build the application
    echo "Building .NET application..."
    dotnet publish -c Release -o /opt/loan-finalizer
    
    # Run database migrations
    echo "Running database migrations..."
    cd /opt/loan-finalizer
    dotnet LoanFinalizer.dll --migrate || echo "Manual migration may be required"
    
    # Enable and start service
    echo "Starting service..."
    systemctl daemon-reload
    systemctl enable loan-finalizer
    systemctl start loan-finalizer
    
    # Check status
    sleep 5
    systemctl status loan-finalizer --no-pager
    
    echo "Deployment complete!"
    echo "Service logs: journalctl -u loan-finalizer -f"
else
    echo "Application files not found. Please deploy source code to /tmp/tier5-dotnet"
    echo "Then run this script again."
fi
DEPLOYEOF

chmod +x /opt/loan-finalizer/deploy-app.sh

# Post-installation message
cat > /etc/motd << 'EOF'
========================================
Tier 5 - Loan Finalizer Service (.NET 8)
Dynatrace OneAgent: Full Stack Mode
========================================

Application: /opt/loan-finalizer/
Service: loan-finalizer.service

To complete installation after deploying source code:
  sudo /opt/loan-finalizer/deploy-app.sh

To view service status:
  systemctl status loan-finalizer

To view logs:
  journalctl -u loan-finalizer -f

Dynatrace OneAgent Status:
  systemctl status oneagent

Database Connection:
  Check /opt/loan-finalizer/app.env
EOF

echo "=== Tier 5 EC2 Instance Setup Complete ==="
echo "OneAgent installed in Full Stack mode"
echo "Application directory ready at: /opt/loan-finalizer/"
echo "Deployment script ready at: /opt/loan-finalizer/deploy-app.sh"
echo ""
echo "Next steps:"
echo "1. Deploy application files to /tmp/tier5-dotnet"
echo "2. Run: sudo /opt/loan-finalizer/deploy-app.sh"
