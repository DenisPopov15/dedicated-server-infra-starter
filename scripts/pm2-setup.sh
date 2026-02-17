#!/bin/bash

# PM2 Setup Script for Node.js Applications
# This script installs PM2 (if not already installed), sets up the application,
# and configures PM2 to start on system reboot
# Usage: ./pm2-setup.sh /path/to/your/project
# Example: ./pm2-setup.sh /home/pi/your-project

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if project path is provided
if [ $# -eq 0 ]; then
    log_error "Project path is required!"
    echo "Usage: $0 /path/to/your/project"
    echo "Example: $0 /home/pi/your-project"
    exit 1
fi

PROJECT_PATH="$1"

# Validate project path
if [ ! -d "$PROJECT_PATH" ]; then
    error_exit "Project path does not exist: $PROJECT_PATH"
fi

log "Starting PM2 setup for project at: $PROJECT_PATH"

# Detect if running as root and determine the actual user
ACTUAL_USER=""
if [ "$EUID" -eq 0 ]; then
    # Running as root, try to get the original user
    if [ -n "${SUDO_USER:-}" ]; then
        ACTUAL_USER="$SUDO_USER"
        log "Detected running as root via sudo. Using user: $ACTUAL_USER"
    else
        # Try to extract user from project path (e.g., /home/pi/...)
        if [[ "$PROJECT_PATH" =~ ^/home/([^/]+) ]]; then
            ACTUAL_USER="${BASH_REMATCH[1]}"
            log "Detected running as root. Inferred user from path: $ACTUAL_USER"
        else
            log_warning "Running as root but cannot determine original user. Will try to find npm in common locations."
        fi
    fi
else
    ACTUAL_USER=$(whoami)
    log "Running as user: $ACTUAL_USER"
fi

# Function to run a command as the actual user (if we're root)
run_as_user() {
    if [ "$EUID" -eq 0 ] && [ -n "$ACTUAL_USER" ]; then
        # Run as the actual user with their full environment
        su - "$ACTUAL_USER" -c "$*"
    else
        # Run normally
        eval "$*"
    fi
}

# Function to check if a command exists for the actual user
command_exists_for_user() {
    local cmd="$1"
    if [ "$EUID" -eq 0 ] && [ -n "$ACTUAL_USER" ]; then
        su - "$ACTUAL_USER" -c "command -v $cmd" &> /dev/null
    else
        command -v "$cmd" &> /dev/null
    fi
}

# Function to get command output from the actual user
get_command_output() {
    local cmd="$1"
    if [ "$EUID" -eq 0 ] && [ -n "$ACTUAL_USER" ]; then
        su - "$ACTUAL_USER" -c "$cmd"
    else
        eval "$cmd"
    fi
}

# Check if PM2 is already installed
if command_exists_for_user "pm2"; then
    PM2_VERSION=$(get_command_output "pm2 --version")
    log_success "PM2 is already installed: v$PM2_VERSION"
else
    log "PM2 is not installed. Installing PM2 globally..."
    
    # Check if npm is available
    if ! command_exists_for_user "npm"; then
        error_exit "npm is not installed for user $ACTUAL_USER. Please install Node.js and npm first."
    fi
    
    # Install PM2 globally
    if run_as_user "npm install -g pm2"; then
        PM2_VERSION=$(get_command_output "pm2 --version")
        log_success "PM2 installed successfully: v$PM2_VERSION"
    else
        error_exit "Failed to install PM2. Make sure you have proper permissions."
    fi
fi

# Navigate to project directory
log "Navigating to project directory: $PROJECT_PATH"
cd "$PROJECT_PATH" || error_exit "Failed to navigate to project directory: $PROJECT_PATH"

# Create logs directory (as the actual user to ensure proper permissions)
log "Creating logs directory..."
if [ "$EUID" -eq 0 ] && [ -n "$ACTUAL_USER" ]; then
    # Create as the actual user
    su - "$ACTUAL_USER" -c "mkdir -p '$PROJECT_PATH/logs'"
    log_success "Logs directory created/verified: $PROJECT_PATH/logs"
else
    if mkdir -p logs; then
        log_success "Logs directory created/verified: $(pwd)/logs"
    else
        error_exit "Failed to create logs directory"
    fi
fi

# Check if ecosystem.config.js exists
if [ ! -f "ecosystem.config.js" ]; then
    error_exit "ecosystem.config.js not found in project directory: $PROJECT_PATH"
else
    log_success "Found ecosystem.config.js"
fi

# Stop any existing PM2 processes for this app (if any)
log "Checking for existing PM2 processes..."
if run_as_user "pm2 list" | grep -q "telegram-bot"; then
    log_warning "Found existing 'telegram-bot' process. Stopping it..."
    run_as_user "pm2 stop telegram-bot" || true
    run_as_user "pm2 delete telegram-bot" || true
fi

# Start application with PM2
log "Starting application with PM2..."
if run_as_user "cd '$PROJECT_PATH' && pm2 start ecosystem.config.js --env production"; then
    log_success "Application started with PM2"
else
    error_exit "Failed to start application with PM2. Check ecosystem.config.js configuration."
fi

# Display PM2 status
log "PM2 process status:"
run_as_user "pm2 list"

# Setup PM2 to start on system reboot
log "Setting up PM2 to start on system reboot..."

# Get the startup command from PM2
STARTUP_CMD=$(run_as_user "pm2 startup" | grep -E "sudo.*pm2" || true)

if [ -n "$STARTUP_CMD" ]; then
    log "PM2 startup command generated. Executing it..."
    log_warning "You may be prompted for your sudo password"
    
    # Execute the startup command
    if eval "$STARTUP_CMD"; then
        log_success "PM2 startup script installed successfully"
    else
        log_warning "Failed to execute PM2 startup command automatically"
        log_warning "Please run the following command manually:"
        echo "$STARTUP_CMD"
    fi
else
    log_warning "Could not generate PM2 startup command automatically"
    log_warning "Please run 'pm2 startup' manually and execute the command it shows"
fi

# Save PM2 process list
log "Saving PM2 process list..."
if run_as_user "pm2 save"; then
    log_success "PM2 process list saved"
else
    log_warning "Failed to save PM2 process list"
fi

# Install PM2 server monitoring module
log "Installing PM2 server monitoring module..."
if run_as_user "pm2 install pm2-server-monit"; then
    log_success "PM2 server monitoring module installed successfully"
else
    log_warning "Failed to install PM2 server monitoring module"
fi

# Configure PM2 server monitoring
log "Configuring PM2 server monitoring..."
run_as_user "pm2 set pm2-server-monit:cpu true"
run_as_user "pm2 set pm2-server-monit:memory true"
run_as_user "pm2 set pm2-server-monit:network true"
run_as_user "pm2 set pm2-server-monit:disk false"
run_as_user "pm2 set pm2-server-monit:interval 20"
log_success "PM2 server monitoring configured"


# Display final status
log_success "PM2 setup completed successfully!"
echo ""
log "PM2 process information:"
run_as_user "pm2 list"
echo ""
log "Useful PM2 commands:"
log "  - View logs: pm2 logs"
log "  - View logs (specific app): pm2 logs telegram-bot"
log "  - Monitor: pm2 monit"
log "  - Restart: pm2 restart telegram-bot"
log "  - Stop: pm2 stop telegram-bot"
log "  - Status: pm2 status"
log "  - Save current list: pm2 save"
echo ""
log_success "Your application is now running with PM2 and will start automatically on system reboot!"