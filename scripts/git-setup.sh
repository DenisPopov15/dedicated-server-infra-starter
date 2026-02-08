#!/bin/bash

# Git Installation and GitHub SSH Key Setup Script
# This script installs Git and sets up an SSH key for GitHub
# Designed for Raspberry Pi and other Linux systems
# Usage: ./git-setup.sh

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# SSH key configuration
SSH_KEY_NAME="github_bot"
SSH_KEY_PATH="$HOME/.ssh/${SSH_KEY_NAME}"
SSH_CONFIG_PATH="$HOME/.ssh/config"

# Function to log messages
log() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to log errors and exit
error_exit() {
    log_error "$1"
    exit 1
}

# Function to check if git is installed
check_git_installed() {
    if command -v git &> /dev/null; then
        return 0
    fi
    return 1
}

# Function to install git
install_git() {
    log "Installing Git..."
    
    # Detect package manager
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu/Raspberry Pi OS
        sudo apt-get update -qq
        sudo apt-get install -y git
    elif command -v yum &> /dev/null; then
        # RHEL/CentOS/Fedora
        sudo yum install -y git
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        sudo pacman -S --noconfirm git
    elif command -v apk &> /dev/null; then
        # Alpine Linux
        sudo apk add --no-cache git
    else
        error_exit "Could not detect package manager. Please install Git manually."
    fi
    
    log_success "Git installed successfully"
}

# Function to check if SSH key exists
check_ssh_key_exists() {
    if [ -f "${SSH_KEY_PATH}" ] && [ -f "${SSH_KEY_PATH}.pub" ]; then
        return 0
    fi
    return 1
}

# Function to generate SSH key
generate_ssh_key() {
    log "Generating ed25519 SSH key for GitHub..."
    
    # Ensure .ssh directory exists
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Remove any partial key files if they exist (shouldn't happen due to check, but be safe)
    if [ -f "${SSH_KEY_PATH}" ]; then
        rm -f "${SSH_KEY_PATH}"
    fi
    if [ -f "${SSH_KEY_PATH}.pub" ]; then
        rm -f "${SSH_KEY_PATH}.pub"
    fi
    
    # Generate ed25519 key (using -f flag and empty passphrase)
    if ssh-keygen -t ed25519 -f "${SSH_KEY_PATH}" -N "" -C "github_bot@$(hostname)" > /dev/null 2>&1; then
        log_success "SSH key generated successfully at ${SSH_KEY_PATH}"
    else
        error_exit "Failed to generate SSH key"
    fi
    
    # Set proper permissions
    chmod 600 "${SSH_KEY_PATH}"
    chmod 644 "${SSH_KEY_PATH}.pub"
}

# Function to configure SSH config for GitHub
configure_ssh_for_github() {
    log "Configuring SSH to use ${SSH_KEY_NAME} key for GitHub..."
    
    # Ensure .ssh directory exists
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Check if config file exists
    if [ ! -f "${SSH_CONFIG_PATH}" ]; then
        touch "${SSH_CONFIG_PATH}"
        chmod 600 "${SSH_CONFIG_PATH}"
        log "Created SSH config file at ${SSH_CONFIG_PATH}"
    fi
    
    # Check if GitHub host entry already exists
    if grep -q "^Host github.com" "${SSH_CONFIG_PATH}"; then
        log_warning "GitHub host entry already exists in SSH config"
        
        # Check if it already uses the correct key
        if grep -A 5 "^Host github.com" "${SSH_CONFIG_PATH}" | grep -q "IdentityFile.*${SSH_KEY_NAME}"; then
            log_success "SSH config already configured correctly for GitHub"
            return 0
        else
            log_warning "Updating existing GitHub host entry to use ${SSH_KEY_NAME} key"
            # Create backup
            cp "${SSH_CONFIG_PATH}" "${SSH_CONFIG_PATH}.bak"
            # Remove old GitHub entry (from "Host github.com" to next "Host" line or end of file)
            # Use awk to remove the block
            awk '
                /^Host github.com/ { in_block=1; next }
                /^Host / && in_block { in_block=0 }
                !in_block { print }
            ' "${SSH_CONFIG_PATH}.bak" > "${SSH_CONFIG_PATH}"
        fi
    fi
    
    # Add GitHub host configuration
    {
        echo ""
        echo "Host github.com"
        echo "    HostName github.com"
        echo "    User git"
        echo "    IdentityFile ${SSH_KEY_PATH}"
        echo "    IdentitiesOnly yes"
    } >> "${SSH_CONFIG_PATH}"
    
    chmod 600 "${SSH_CONFIG_PATH}"
    log_success "SSH config updated for GitHub"
}

# Function to display public key
display_public_key() {
    if [ -f "${SSH_KEY_PATH}.pub" ]; then
        echo
        log_success "GitHub SSH Public Key:"
        echo "========================================"
        cat "${SSH_KEY_PATH}.pub"
        echo "========================================"
        echo
        log "Add this public key to your GitHub account:"
        log "1. Go to: https://github.com/settings/keys"
        log "2. Click 'New SSH key'"
        log "3. Paste the key above"
        log "4. Give it a descriptive title (e.g., 'Raspberry Pi Bot')"
        echo
    else
        log_error "Public key file not found at ${SSH_KEY_PATH}.pub"
    fi
}

# Function to verify git installation
verify_git_installation() {
    log "Verifying Git installation..."
    
    if command -v git &> /dev/null; then
        GIT_VERSION=$(git --version)
        log_success "Git version: $GIT_VERSION"
    else
        error_exit "Git command not found after installation"
    fi
}

# Function to verify SSH key setup
verify_ssh_setup() {
    log "Verifying SSH key setup..."
    
    if [ -f "${SSH_KEY_PATH}" ] && [ -f "${SSH_KEY_PATH}.pub" ]; then
        log_success "SSH key files exist"
        
        # Check key type
        KEY_TYPE=$(ssh-keygen -l -f "${SSH_KEY_PATH}.pub" | awk '{print $4}')
        if [ "$KEY_TYPE" = "ED25519" ]; then
            log_success "SSH key type: ED25519"
        else
            log_warning "SSH key type: $KEY_TYPE (expected ED25519)"
        fi
    else
        error_exit "SSH key files not found"
    fi
    
    # Verify SSH config
    if [ -f "${SSH_CONFIG_PATH}" ]; then
        if grep -q "^Host github.com" "${SSH_CONFIG_PATH}"; then
            log_success "SSH config contains GitHub host entry"
        else
            log_warning "SSH config does not contain GitHub host entry"
        fi
    fi
}

# Function to display post-installation instructions
show_post_install_instructions() {
    echo
    log_success "Git and GitHub SSH key setup completed!"
    echo
    log "Next steps:"
    echo "1. Add the SSH public key (shown above) to your GitHub account"
    echo "2. Test the connection with: ssh -T git@github.com"
    echo "3. You can now clone repositories using: git clone git@github.com:username/repo.git"
    echo
    log "Useful Git commands:"
    echo "  - git --version              # Check Git version"
    echo "  - git config --global user.name \"Your Name\"     # Set Git username"
    echo "  - git config --global user.email \"your@email.com\" # Set Git email"
    echo "  - ssh -T git@github.com      # Test GitHub SSH connection"
    echo
}

# Main installation function
main() {
    echo "========================================"
    echo "Git Installation and GitHub SSH Setup"
    echo "========================================"
    echo
    
    log "Starting Git installation and GitHub SSH key setup..."
    
    # Check if git is already installed
    if check_git_installed; then
        log_success "Git is already installed: $(git --version)"
    else
        log "Git is not installed. Installing Git..."
        install_git
    fi
    
    # Verify git installation
    verify_git_installation
    
    # Check if SSH key already exists
    if check_ssh_key_exists; then
        log_success "SSH key already exists at ${SSH_KEY_PATH}"
    else
        log "SSH key not found. Generating new SSH key..."
        generate_ssh_key
    fi
    
    # Configure SSH for GitHub
    configure_ssh_for_github
    
    # Verify SSH setup
    verify_ssh_setup
    
    # Display public key
    display_public_key
    
    # Show post-installation instructions
    show_post_install_instructions
    
    log_success "Setup script completed successfully!"
}

# Run main function
main "$@"

