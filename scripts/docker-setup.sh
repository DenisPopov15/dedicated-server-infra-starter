#!/bin/bash

# Docker and Docker Compose Installation Script for Ubuntu 22.04 LTS
# Usage: ./install_docker.sh [user1] [user2] [user3] ...
# If no usernames are provided, current user will be added to docker group
# Examples:
#   ./install_docker.sh                    # Add current user
#   ./install_docker.sh alice bob          # Add alice and bob
#   ./install_docker.sh root github deploy # Add multiple users including root

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "This script is running as root. It's recommended to run as a regular user with sudo privileges."
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to check if Docker is already installed
check_existing_docker() {
    if command -v docker &> /dev/null; then
        print_warning "Docker is already installed: $(docker --version)"
        read -p "Do you want to continue and potentially reinstall/update? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping Docker installation. Will only add users to docker group if specified."
            return 1
        fi
    fi
    return 0
}

# Function to check Ubuntu version
check_ubuntu_version() {
    if ! grep -q "Ubuntu 22.04" /etc/os-release; then
        print_warning "This script is designed for Ubuntu 22.04 LTS. Your system might not be compatible."
        print_status "Detected OS: $(lsb_release -d | cut -f2)"
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to update system
update_system() {
    print_status "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    print_success "System updated successfully"
}

# Function to install prerequisites
install_prerequisites() {
    print_status "Installing prerequisites..."
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        software-properties-common \
        gnupg \
        lsb-release
    print_success "Prerequisites installed successfully"
}

# Function to add Docker GPG key
add_docker_gpg_key() {
    print_status "Adding Docker's official GPG key..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    print_success "Docker GPG key added successfully"
}

# Function to add Docker repository
add_docker_repository() {
    print_status "Adding Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    print_success "Docker repository added successfully"
}

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."
    sudo apt install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    print_success "Docker installed successfully"
}

# Function to start and enable Docker service
start_docker_service() {
    print_status "Starting and enabling Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
    print_success "Docker service started and enabled"
}

# Function to add users to docker group
add_users_to_docker_group() {
    local users=("$@")

    # If no users specified, use current user (but not if running as root)
    if [[ ${#users[@]} -eq 0 ]]; then
        if [[ $EUID -eq 0 ]]; then
            print_error "When running as root, you must specify at least one username as an argument."
            print_status "Usage: $0 [user1] [user2] [user3] ..."
            print_status "Example: $0 alice bob github"
            exit 1
        fi
        users=("$USER")
    fi

    print_status "Adding users to docker group..."
    local added_users=()
    local failed_users=()

    for username in "${users[@]}"; do
        # Check if user exists
        if id "$username" &>/dev/null; then
            print_status "Adding user '$username' to docker group..."
            if sudo usermod -aG docker "$username"; then
                added_users+=("$username")
                print_success "User '$username' added to docker group"
            else
                failed_users+=("$username")
                print_error "Failed to add user '$username' to docker group"
            fi
        else
            print_warning "User '$username' does not exist on this system, skipping..."
            failed_users+=("$username")
        fi
    done

    # Summary
    if [[ ${#added_users[@]} -gt 0 ]]; then
        echo
        print_success "Successfully added ${#added_users[@]} user(s) to docker group:"
        printf '  - %s\n' "${added_users[@]}"
        print_warning "These users need to log out and back in (or restart) for group changes to take effect"
    fi

    if [[ ${#failed_users[@]} -gt 0 ]]; then
        echo
        print_warning "Failed to add ${#failed_users[@]} user(s):"
        printf '  - %s\n' "${failed_users[@]}"
    fi
}

# Function to verify installation
verify_installation() {
    print_status "Verifying Docker installation..."

    # Check Docker version
    docker_version=$(docker --version)
    print_success "Docker version: $docker_version"

    # Check Docker Compose version
    compose_version=$(docker compose version)
    print_success "Docker Compose version: $compose_version"

    # Test Docker with hello-world (only if not running as root)
    if [[ $EUID -ne 0 ]]; then
        print_status "Testing Docker with hello-world container..."
        if sudo docker run --rm hello-world > /dev/null 2>&1; then
            print_success "Docker test completed successfully"
        else
            print_warning "Docker test failed, but installation appears complete"
        fi
    else
        print_status "Skipping Docker test (running as root)"
    fi
}

# Function to display post-installation instructions
show_post_install_instructions() {
    echo
    print_success "Docker and Docker Compose installation completed!"
    echo
    print_status "Post-installation steps:"
    echo "1. Users need to log out and back in (or restart) for group changes to take effect"
    echo "2. After logging back in, test Docker without sudo:"
    echo "   docker run hello-world"
    echo "3. Test Docker Compose:"
    echo "   docker compose --help"
    echo
    print_status "Useful Docker commands:"
    echo "- docker --version                 # Check Docker version"
    echo "- docker compose version          # Check Docker Compose version"
    echo "- docker ps                       # List running containers"
    echo "- docker images                   # List Docker images"
    echo "- sudo systemctl status docker    # Check Docker service status"
    echo
}

# Main installation function
main() {
    echo "========================================"
    echo "Docker Installation Script for Ubuntu 22.04 LTS"
    echo "========================================"
    echo

    check_root
    check_ubuntu_version

    # Check if Docker is already installed
    local skip_install=false
    if ! check_existing_docker; then
        skip_install=true
    fi

    print_status "Starting Docker installation process..."

    if [[ "$skip_install" = false ]]; then
        update_system
        install_prerequisites
        add_docker_gpg_key
        add_docker_repository
        install_docker
        start_docker_service
        verify_installation
    else
        print_status "Skipping Docker installation steps..."
    fi

    # Always try to add users to docker group if specified
    if [[ $# -gt 0 ]] || [[ "$skip_install" = true ]]; then
        add_users_to_docker_group "$@"
    fi

    show_post_install_instructions

    print_success "Installation script completed successfully!"
}

# Run main function with all arguments
main "$@"