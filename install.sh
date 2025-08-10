#!/bin/bash

# 🚀 Nuclei Distributed Scanner - Robust Installation Script
# This script installs and configures everything needed to run the distributed scanner

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="nuclei-distributed"
INSTALL_DIR="/opt/${PROJECT_NAME}"
SERVICE_USER="nuclei"
COMPOSE_FILE="docker-compose.full.yml"
REDIS_PASSWORD=""
MAIN_SERVER_IP=""
DO_API_TOKEN=""

# Logging
LOG_FILE="/var/log/nuclei-install.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

print_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║           🎯 Nuclei Distributed Scanner Installer             ║"
    echo "║                                                                ║"
    echo "║     Automated installation of distributed vulnerability        ║"
    echo "║     scanner with Docker, Redis, and all dependencies          ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Installation failed. Check $LOG_FILE for details.${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Pre-flight checks
preflight_checks() {
    log "Running pre-flight checks..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Please use sudo."
    fi
    
    # Store the original directory (where script was executed from)
    ORIGINAL_DIR="$PWD"
    log "Script executed from: $ORIGINAL_DIR"
    
    # Check if we're in the project directory
    if [[ ! -f "docker/Dockerfile.full" ]]; then
        error "This script must be run from the nuclei-cloud project directory. Missing docker/Dockerfile.full"
    fi
    
    if [[ ! -f "docker/$COMPOSE_FILE" ]]; then
        error "Missing required file: docker/$COMPOSE_FILE"
    fi
    
    if [[ ! -f "go.mod" ]]; then
        error "Missing go.mod file. Are you in the correct project directory?"
    fi
    
    log "Pre-flight checks passed"
}

# Detect operating system
detect_os() {
    log "Detecting operating system..."
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS="$NAME $VERSION"
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    else
        error "Cannot detect operating system. /etc/os-release not found."
    fi
    
    info "Detected OS: $OS"
}

# Detect server IP
detect_server_ip() {
    log "Detecting server external IP address..."
    
    # Try multiple methods to get external IP
    MAIN_SERVER_IP=$(curl -s https://ipv4.icanhazip.com/ || curl -s https://api.ipify.org || curl -s https://checkip.amazonaws.com/ | tr -d '\n')
    
    if [[ -z "$MAIN_SERVER_IP" ]]; then
        warn "Could not auto-detect external IP. Trying local network IP..."
        MAIN_SERVER_IP=$(hostname -I | awk '{print $1}')
    fi
    
    if [[ -z "$MAIN_SERVER_IP" ]]; then
        error "Could not detect server IP address"
    fi
    
    info "Using external IP: $MAIN_SERVER_IP"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -qq
            apt-get upgrade -y -qq
            apt-get install -y curl wget git ufw openssl jq make rsync
            ;;
        centos|rhel)
            yum update -y -q
            yum install -y curl wget git firewalld openssl jq make rsync
            ;;
        fedora)
            dnf update -y -q
            dnf install -y curl wget git firewalld openssl jq make rsync
            ;;
        *)
            error "Unsupported operating system: $OS_ID"
            ;;
    esac
}

# Install Docker
install_docker() {
    log "Installing Docker..."
    
    if command -v docker >/dev/null 2>&1; then
        info "Docker is already installed"
        docker --version
        return 0
    fi
    
    case "$OS_ID" in
        ubuntu|debian)
            # Add Docker's official GPG key
            curl -fsSL https://download.docker.com/linux/$OS_ID/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            
            # Add Docker repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_ID $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker
            apt-get update -qq
            apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        centos|rhel)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        fedora)
            dnf install -y dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io
            ;;
    esac
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log "Docker installed successfully"
}

# Install Docker Compose
install_docker_compose() {
    log "Installing Docker Compose..."
    
    if command -v docker-compose >/dev/null 2>&1; then
        info "Docker Compose is already installed"
        docker-compose --version
        return 0
    fi
    
    # Install latest version of Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    # Verify installation
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose --version
        log "Docker Compose installed successfully"
    else
        error "Failed to install Docker Compose"
    fi
}

# Create service user
create_service_user() {
    log "Creating service user: $SERVICE_USER"
    
    if id "$SERVICE_USER" &>/dev/null; then
        info "User $SERVICE_USER already exists"
        return 0
    fi
    
    # Create user with home directory
    useradd -r -m -s /bin/bash -d /home/$SERVICE_USER $SERVICE_USER
    
    # Add to docker group
    usermod -aG docker $SERVICE_USER
    
    log "Service user created successfully"
}

# Setup project directory
setup_project_directory() {
    log "Setting up project directory: $INSTALL_DIR"
    
    # Ensure we're in the original directory
    cd "$ORIGINAL_DIR"
    
    # Create and clean installation directory
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR"/*
    rm -rf "$INSTALL_DIR"/.[^.]*
    
    info "Copying project files from $ORIGINAL_DIR to $INSTALL_DIR"
    
    # Use rsync for reliable copying (fallback to cp if rsync not available)
    if command -v rsync >/dev/null 2>&1; then
        rsync -av --exclude='.git' --exclude='node_modules' --exclude='*.log' ./ "$INSTALL_DIR/"
    else
        # Fallback to cp
        cp -r * "$INSTALL_DIR/" 2>/dev/null || true
        for file in .[^.]*; do
            if [[ -e "$file" && "$file" != ".git" ]]; then
                cp -r "$file" "$INSTALL_DIR/" 2>/dev/null || true
            fi
        done
    fi
    
    # Verify critical files
    local required_files=(
        "docker/Dockerfile.full"
        "docker/$COMPOSE_FILE"
        "go.mod"
        "pkg/api/routes.go"
        "web/package.json"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$INSTALL_DIR/$file" ]]; then
            error "Critical file missing: $file"
        fi
    done
    
    # Set ownership and permissions
    chown -R $SERVICE_USER:$SERVICE_USER "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
    chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true
    
    info "Project files copied successfully"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    case "$OS_ID" in
        ubuntu|debian)
            ufw --force enable
            ufw allow ssh
            ufw allow 8080/tcp comment "Nuclei Scanner"
            ufw allow 80/tcp comment "HTTP"
            ufw allow 443/tcp comment "HTTPS"
            ufw reload
            ;;
        centos|rhel|fedora)
            systemctl start firewalld
            systemctl enable firewalld
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-port=8080/tcp
            firewall-cmd --permanent --add-port=80/tcp
            firewall-cmd --permanent --add-port=443/tcp
            firewall-cmd --reload
            ;;
    esac
    
    info "Firewall configured"
}

# Gather configuration
gather_configuration() {
    log "Gathering configuration information..."
    
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║ DIGITALOCEAN API TOKEN                                                       ║"
    echo "║                                                                              ║"
    echo "║ You need a DigitalOcean API token to create worker droplets.                ║"
    echo "║ Get one at: https://cloud.digitalocean.com/account/api/tokens               ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Get DigitalOcean API token
    while [[ -z "$DO_API_TOKEN" ]]; do
        read -p "Enter your DigitalOcean API Token: " DO_API_TOKEN
        if [[ -z "$DO_API_TOKEN" ]]; then
            echo "API token cannot be empty. Please try again."
        fi
    done
    
    # Confirm server IP
    echo
    echo "Detected server IP: $MAIN_SERVER_IP"
    read -p "Is this correct? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        read -p "Enter the correct server IP: " MAIN_SERVER_IP
    fi
    
    # Generate Redis password
    REDIS_PASSWORD=$(openssl rand -base64 32)
}

# Generate environment configuration
generate_env_config() {
    log "Generating environment configuration..."
    
    cd "$INSTALL_DIR"
    
    # Create .env file
    cat > .env << EOF
# Nuclei Distributed Scanner Configuration
# Generated automatically by installer

# DigitalOcean Configuration
DO_API_TOKEN=$DO_API_TOKEN

# Server Configuration
MAIN_SERVER_IP=$MAIN_SERVER_IP
PORT=8080

# Redis Configuration
REDIS_URL=redis:6379
REDIS_PASSWORD=$REDIS_PASSWORD

# Application Settings
GIN_MODE=release
LOG_LEVEL=info

# Worker Settings
AUTO_DESTROY=true
MAX_AGE_HOURS=2
MAX_WORKERS=10
WORKER_TIMEOUT=3600

# Security Settings
SESSION_SECRET=$(openssl rand -base64 32)

# Optional: Custom Nuclei Settings
NUCLEI_RATE_LIMIT=10
NUCLEI_TIMEOUT=30
NUCLEI_RETRIES=2
EOF
    
    # Set proper permissions
    chown $SERVICE_USER:$SERVICE_USER .env
    chmod 600 .env
    
    info "Environment configuration created"
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service..."
    
    cat > /etc/systemd/system/nuclei-distributed.service << EOF
[Unit]
Description=Nuclei Distributed Scanner
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
User=$SERVICE_USER
Group=$SERVICE_USER
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/docker-compose -f $INSTALL_DIR/docker/$COMPOSE_FILE up -d --build
ExecStop=/usr/local/bin/docker-compose -f $INSTALL_DIR/docker/$COMPOSE_FILE down
ExecReload=/usr/local/bin/docker-compose -f $INSTALL_DIR/docker/$COMPOSE_FILE restart
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    systemctl enable nuclei-distributed
    
    info "Systemd service created and enabled"
}

# Start application
start_application() {
    log "Starting Nuclei Distributed Scanner..."
    
    cd "$INSTALL_DIR"
    
    # Set environment variables
    set -a
    source .env
    set +a
    
    # Build and start services
    info "Building and starting Docker containers..."
    docker-compose -f docker/$COMPOSE_FILE up -d --build
    
    # Wait for services to start
    log "Waiting for services to initialize..."
    sleep 30
    
    # Check health
    for i in {1..10}; do
        if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
            log "Application started successfully!"
            break
        elif [[ $i -eq 10 ]]; then
            error "Application failed to start. Check logs with: docker-compose -f docker/$COMPOSE_FILE logs"
        else
            info "Waiting for application to start... ($i/10)"
            sleep 10
        fi
    done
}

# Create management scripts
create_management_scripts() {
    log "Creating management scripts..."
    
    # Create start script
    cat > /usr/local/bin/nuclei-start << EOF
#!/bin/bash
cd $INSTALL_DIR
set -a; source .env; set +a
docker-compose -f docker/$COMPOSE_FILE up -d
echo "Nuclei Distributed Scanner started"
echo "Web UI: http://$MAIN_SERVER_IP:8080"
EOF
    
    # Create stop script
    cat > /usr/local/bin/nuclei-stop << EOF
#!/bin/bash
cd $INSTALL_DIR
docker-compose -f docker/$COMPOSE_FILE down
echo "Nuclei Distributed Scanner stopped"
EOF
    
    # Create status script
    cat > /usr/local/bin/nuclei-status << EOF
#!/bin/bash
cd $INSTALL_DIR
echo "=== Service Status ==="
docker-compose -f docker/$COMPOSE_FILE ps
echo
echo "=== Health Check ==="
curl -sf http://localhost:8080/health && echo "✅ API is healthy" || echo "❌ API is not responding"
echo
echo "=== Recent Logs ==="
docker-compose -f docker/$COMPOSE_FILE logs --tail=10
EOF
    
    # Create logs script
    cat > /usr/local/bin/nuclei-logs << EOF
#!/bin/bash
cd $INSTALL_DIR
docker-compose -f docker/$COMPOSE_FILE logs -f
EOF
    
    # Create restart script
    cat > /usr/local/bin/nuclei-restart << EOF
#!/bin/bash
cd $INSTALL_DIR
set -a; source .env; set +a
echo "Restarting Nuclei Distributed Scanner..."
docker-compose -f docker/$COMPOSE_FILE down
docker-compose -f docker/$COMPOSE_FILE up -d --build
echo "Restart complete"
EOF
    
    # Make scripts executable
    chmod +x /usr/local/bin/nuclei-*
    
    info "Management scripts created in /usr/local/bin/"
}

# Final setup and verification
final_setup() {
    log "Performing final setup and verification..."
    
    # Test Docker Compose
    cd "$INSTALL_DIR"
    if ! docker-compose -f docker/$COMPOSE_FILE config >/dev/null; then
        error "Docker Compose configuration is invalid"
    fi
    
    # Start the systemd service
    systemctl start nuclei-distributed
    
    info "Installation completed successfully!"
    
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           🎉 INSTALLATION COMPLETE 🎉                      ║"
    echo "║                                                                              ║"
    echo "║  Nuclei Distributed Scanner is now running!                                 ║"
    echo "║                                                                              ║"
    echo "║  🌐 Web UI: http://$MAIN_SERVER_IP:8080                     ║"
    echo "║  📊 API Docs: http://$MAIN_SERVER_IP:8080/api              ║"
    echo "║                                                                              ║"
    echo "║  📋 Management Commands:                                                     ║"
    echo "║     nuclei-start    - Start the scanner                                     ║"
    echo "║     nuclei-stop     - Stop the scanner                                      ║"
    echo "║     nuclei-status   - Check status                                          ║"
    echo "║     nuclei-logs     - View logs                                             ║"
    echo "║     nuclei-restart  - Restart services                                      ║"
    echo "║                                                                              ║"
    echo "║  📝 Logs: $LOG_FILE                               ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Main installation flow
main() {
    print_banner
    preflight_checks
    detect_os
    detect_server_ip
    update_system
    install_docker
    install_docker_compose
    create_service_user
    setup_project_directory
    configure_firewall
    gather_configuration
    generate_env_config
    create_systemd_service
    create_management_scripts
    start_application
    final_setup
}

# Run main function
main "$@"