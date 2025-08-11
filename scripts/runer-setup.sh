#!/bin/bash

# GitHub Actions Runner Setup Script
#
# Usage:
#   Local: ./runer-setup.sh <orgName> <token> <labels>
#   Remote: curl -s <script-url> | bash -s <orgName> <token> <labels>
#
# Examples:
#   ./runer-setup.sh my-org ghp_xxxxxxxxxxxx deployment,development
#   curl -s https://example.com/runer-setup.sh | sudo bash -s my-org ghp_xxxxxxxxxxxx deployment,development
#
# Prerequisites:
#   - Must run as root (use sudo)
#   - Server must have internet access
#   - GitHub token must have admin:org permissions for runner registration

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Function to log errors and exit
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Parse command line arguments
if [ $# -ne 3 ]; then
    error_exit "Usage: $0 <orgName> <token> <labels>
    Example: $0 my-org ghp_xxxxxxxxxxxx deployment,development"
fi

ORG_NAME="$1"
TOKEN="$2"
LABELS="$3"
RUNNER_USER="github"
RUNNER_VERSION="2.327.1"
RUNNER_HOME="/home/${RUNNER_USER}"

log "Starting GitHub Actions Runner setup..."
log "Organization: ${ORG_NAME}"
log "Labels: ${LABELS}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root"
fi

# Create runner user
log "Creating runner user: ${RUNNER_USER}"
if ! id "${RUNNER_USER}" &>/dev/null; then
    adduser --disabled-password --gecos "" "${RUNNER_USER}" || error_exit "Failed to create user ${RUNNER_USER}"
    passwd -l "${RUNNER_USER}" || error_exit "Failed to lock password for ${RUNNER_USER}"
    log "User ${RUNNER_USER} created successfully"
else
    log "User ${RUNNER_USER} already exists"
fi

# Setup runner as the runner user
log "Setting up runner in ${RUNNER_HOME}/actions-runner"
sudo -u "${RUNNER_USER}" bash << EOF
set -euo pipefail
cd "${RUNNER_HOME}"

# Create actions-runner directory
if [ ! -d "actions-runner" ]; then
    mkdir actions-runner
fi
cd actions-runner

# Download runner if not already present
if [ ! -f "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" ]; then
    echo "Downloading GitHub Actions Runner v${RUNNER_VERSION}..."
    curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz || exit 1
fi

# Verify checksum
echo "d68ac1f500b747d1271d9e52661c408d56cffd226974f68b7dc813e30b9e0575  actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | shasum -a 256 -c || exit 1

# Extract if not already extracted
if [ ! -f "config.sh" ]; then
    echo "Extracting runner..."
    tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz || exit 1
fi

# Configure runner
echo "Configuring runner..."
./config.sh --url https://github.com/${ORG_NAME} --token ${TOKEN} --labels ${LABELS} --unattended || exit 1
EOF

if [ $? -ne 0 ]; then
    error_exit "Failed to setup runner as user ${RUNNER_USER}"
fi

# Install and start service as root
log "Installing runner service..."
cd "${RUNNER_HOME}/actions-runner"
sudo ./svc.sh install "${RUNNER_USER}" || error_exit "Failed to install runner service"

log "Starting runner service..."
sudo ./svc.sh start || error_exit "Failed to start runner service"

log "GitHub Actions Runner setup completed successfully!"
log "Service status:"
sudo ./svc.sh status || true