#!/bin/bash

# 🚀 Nuclei Distributed Scanner - One-Click Installation Script
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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Please use: sudo $0"
    fi
}

# Detect operating system
detect_os() {
    log "Detecting operating system..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [[ -f /etc/redhat-release ]]; then
        OS="Red Hat Enterprise Linux"
        VER=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    else
        error "Cannot detect operating system"
    fi
    
    info "Detected OS: $OS $VER"
}

# Generate secure passwords
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Get server external IP
get_external_ip() {
    log "Detecting server external IP address..."
    
    # Try multiple methods to get external IP
    EXTERNAL_IP=$(curl -s ipv4.icanhazip.com 2>/dev/null || \
                  curl -s ifconfig.me 2>/dev/null || \
                  curl -s ipinfo.io/ip 2>/dev/null || \
                  wget -qO- http://ipecho.net/plain 2>/dev/null)
    
    if [[ -z "$EXTERNAL_IP" ]]; then
        warn "Could not automatically detect external IP"
        read -p "Please enter your server's external IP address: " EXTERNAL_IP
    fi
    
    # Validate IP format
    if [[ ! $EXTERNAL_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error "Invalid IP address format: $EXTERNAL_IP"
    fi
    
    MAIN_SERVER_IP="$EXTERNAL_IP"
    info "Using external IP: $MAIN_SERVER_IP"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    
    case "$OS" in
        *"Ubuntu"*|*"Debian"*)
            apt-get update && apt-get upgrade -y
            apt-get install -y curl wget git ufw openssl jq make
            ;;
        *"CentOS"*|*"Red Hat"*|*"Rocky"*|*"AlmaLinux"*)
            yum update -y
            yum install -y curl wget git firewalld openssl jq make
            ;;
        *"Fedora"*)
            dnf update -y
            dnf install -y curl wget git firewalld openssl jq make
            ;;
        *)
            warn "Unsupported OS. Attempting to continue..."
            ;;
    esac
}

# Install Docker
install_docker() {
    log "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        info "Docker is already installed"
        docker --version
        return 0
    fi
    
    # Install Docker using official script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add nuclei user to docker group (will be created later)
    usermod -aG docker root
    
    log "Docker installed successfully"
    docker --version
    
    # Clean up
    rm -f get-docker.sh
}

# Install Docker Compose
install_docker_compose() {
    log "Installing Docker Compose..."
    
    # Check if Docker Compose is already installed
    if command -v docker-compose &> /dev/null; then
        info "Docker Compose is already installed"
        docker-compose --version
        return 0
    fi
    
    # Get latest version
    LATEST_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create symlink for easier access
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log "Docker Compose installed successfully"
    docker-compose --version
}

# Create service user
create_service_user() {
    log "Creating service user: $SERVICE_USER"
    
    # Check if user already exists
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
    
    # Store the original directory where the script was called from
    ORIGINAL_DIR="$PWD"
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    
    # Clone or update repository
    if [[ -d ".git" ]]; then
        info "Updating existing installation..."
        git pull origin main || git pull origin master
    else
        info "Fresh installation..."
        
        info "Original directory: $ORIGINAL_DIR"
        info "Install directory: $INSTALL_DIR"
        
        # Check if we have the required files in the original directory
        if [[ -f "$ORIGINAL_DIR/docker/Dockerfile.main" ]]; then
            info "Found Dockerfile.main in original directory: $ORIGINAL_DIR"
            info "Copying files from $ORIGINAL_DIR to $INSTALL_DIR"
            
            # Copy all files and directories
            cp -r "$ORIGINAL_DIR"/* "$INSTALL_DIR"/ 2>/dev/null || true
            
            # Copy hidden files (like .env) but skip . and ..
            find "$ORIGINAL_DIR" -maxdepth 1 -name '.*' ! -name '.' ! -name '..' -exec cp -r {} "$INSTALL_DIR"/ \; 2>/dev/null || true
            
            # Verify critical files were copied
            if [[ ! -f "$INSTALL_DIR/docker/docker-compose.prod.yml" ]]; then
                error "Failed to copy docker-compose.prod.yml to $INSTALL_DIR"
            fi
            
            info "Files copied successfully. Contents of $INSTALL_DIR:"
            ls -la "$INSTALL_DIR"
        else
            # Fallback: try script directory
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            info "Trying script directory: $SCRIPT_DIR"
            
            if [[ -f "$SCRIPT_DIR/docker/Dockerfile.main" ]]; then
                info "Found Dockerfile.main in script directory"
                cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR"/ 2>/dev/null || true
                cp -r "$SCRIPT_DIR"/.[^.]* "$INSTALL_DIR"/ 2>/dev/null || true
            else
                info "Debug information:"
                info "Original directory contents: $(ls -la $ORIGINAL_DIR 2>/dev/null || echo 'Original directory not accessible')"
                info "Script directory contents: $(ls -la $SCRIPT_DIR 2>/dev/null || echo 'Script directory not accessible')"
                error "Cannot find required files. Checked $ORIGINAL_DIR/docker/Dockerfile.main and $SCRIPT_DIR/docker/Dockerfile.main"
            fi
        fi
    fi
    
    # Change to install directory after copying
    cd "$INSTALL_DIR"
    
    # Set ownership
    chown -R $SERVICE_USER:$SERVICE_USER "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
    chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    case "$OS" in
        *"Ubuntu"*|*"Debian"*)
            # UFW configuration
            ufw --force enable
            ufw allow ssh
            ufw allow 8080/tcp comment "Nuclei Distributed Scanner"
            ufw allow 80/tcp comment "HTTP"
            ufw allow 443/tcp comment "HTTPS"
            ufw reload
            info "UFW firewall configured"
            ;;
        *"CentOS"*|*"Red Hat"*|*"Rocky"*|*"AlmaLinux"*|*"Fedora"*)
            # Firewalld configuration
            systemctl start firewalld
            systemctl enable firewalld
            firewall-cmd --permanent --add-port=8080/tcp
            firewall-cmd --permanent --add-port=80/tcp
            firewall-cmd --permanent --add-port=443/tcp
            firewall-cmd --reload
            info "Firewalld configured"
            ;;
        *)
            warn "Could not configure firewall automatically. Please ensure ports 8080, 80, and 443 are open."
            ;;
    esac
}

# Get user input
get_user_input() {
    log "Gathering configuration information..."
    
    # Get DigitalOcean API Token
    if [[ -z "$DO_API_TOKEN" ]]; then
        echo
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║                            DIGITALOCEAN API TOKEN                           ║${NC}"
        echo -e "${YELLOW}║                                                                              ║${NC}"
        echo -e "${YELLOW}║ You need a DigitalOcean API token to create worker droplets.               ║${NC}"
        echo -e "${YELLOW}║ Get one at: https://cloud.digitalocean.com/account/api/tokens               ║${NC}"
        echo -e "${YELLOW}║                                                                              ║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo
        
        while [[ -z "$DO_API_TOKEN" ]]; do
            read -p "Enter your DigitalOcean API Token: " DO_API_TOKEN
            if [[ -z "$DO_API_TOKEN" ]]; then
                warn "API Token is required to proceed"
            fi
        done
    fi
    
    # Confirm server IP
    echo
    echo -e "${BLUE}Detected server IP: $MAIN_SERVER_IP${NC}"
    read -p "Is this correct? (y/n): " confirm_ip
    if [[ $confirm_ip =~ ^[Nn] ]]; then
        read -p "Enter the correct external IP: " MAIN_SERVER_IP
    fi
}

# Generate environment configuration
generate_environment() {
    log "Generating environment configuration..."
    
    # Generate secure Redis password
    REDIS_PASSWORD=$(generate_password)
    
    # Create .env file
    cat > "$INSTALL_DIR/.env" << EOF
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
AUTO_DESTROY=true
MAX_AGE_HOURS=2

# Security Settings
NUCLEI_RATE_LIMIT=10
NUCLEI_TIMEOUT=30
NUCLEI_RETRIES=2

# Generated on $(date)
EOF
    
    # Set proper permissions
    chown $SERVICE_USER:$SERVICE_USER "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    
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
ExecStart=/usr/local/bin/docker-compose -f /opt/nuclei-distributed/docker/docker-compose.prod.yml up -d --build
ExecStop=/usr/local/bin/docker-compose -f /opt/nuclei-distributed/docker/docker-compose.prod.yml down
ExecReload=/usr/local/bin/docker-compose -f /opt/nuclei-distributed/docker/docker-compose.prod.yml restart
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    systemctl enable nuclei-distributed
    
    info "Systemd service created and enabled"
}

# Install and start application
start_application() {
    log "Starting Nuclei Distributed Scanner..."
    
    cd "$INSTALL_DIR"
    
    # Verify files were copied correctly
    if [[ ! -f "docker/docker-compose.prod.yml" ]]; then
        error "docker/docker-compose.prod.yml not found in $INSTALL_DIR. Files may not have been copied correctly."
    fi
    
    # Export environment variables for docker-compose
    set -a  # automatically export all variables
    source .env
    set +a  # stop auto-exporting
    
    # Build and start services
    docker-compose -f docker/docker-compose.prod.yml up -d --build
    
    # Wait for services to start
    sleep 10
    
    # Check if services are running
    if docker-compose -f docker/docker-compose.prod.yml ps | grep -q "Up"; then
        log "Application started successfully!"
    else
        error "Failed to start application. Check logs with: docker-compose -f docker/docker-compose.prod.yml logs"
    fi
}

# Create management scripts
create_management_scripts() {
    log "Creating management scripts..."
    
    # Create start script
    cat > /usr/local/bin/nuclei-start << 'EOF'
#!/bin/bash
cd /opt/nuclei-distributed
docker-compose -f docker/docker-compose.prod.yml up -d
echo "Nuclei Distributed Scanner started"
echo "Access at: http://$(hostname -I | awk '{print $1}'):8080"
EOF
    
    # Create stop script
    cat > /usr/local/bin/nuclei-stop << 'EOF'
#!/bin/bash
cd /opt/nuclei-distributed
docker-compose -f docker/docker-compose.prod.yml down
echo "Nuclei Distributed Scanner stopped"
EOF
    
    # Create status script
    cat > /usr/local/bin/nuclei-status << 'EOF'
#!/bin/bash
cd /opt/nuclei-distributed
echo "=== Service Status ==="
docker-compose -f docker/docker-compose.prod.yml ps
echo
echo "=== Recent Logs ==="
docker-compose -f docker/docker-compose.prod.yml logs --tail=10
EOF
    
    # Create logs script
    cat > /usr/local/bin/nuclei-logs << 'EOF'
#!/bin/bash
cd /opt/nuclei-distributed
docker-compose -f docker/docker-compose.prod.yml logs -f
EOF
    
    # Create cleanup script
    cat > /usr/local/bin/nuclei-cleanup << 'EOF'
#!/bin/bash
cd /opt/nuclei-distributed
./scripts/cleanup.sh
echo "Old droplets cleaned up"
EOF
    
    # Make scripts executable
    chmod +x /usr/local/bin/nuclei-*
    
    info "Management scripts created in /usr/local/bin/"
}

# Perform health check
health_check() {
    log "Performing health check..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s -f "http://localhost:8080/health" > /dev/null; then
            log "Health check passed!"
            return 0
        fi
        
        info "Waiting for application to start... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    warn "Health check failed. Application may not be ready yet."
    info "Check logs with: nuclei-logs"
    return 1
}

# Print installation summary
print_summary() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                        🎉 INSTALLATION COMPLETE! 🎉                        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}📋 Installation Summary:${NC}"
    echo -e "   • Location: ${YELLOW}$INSTALL_DIR${NC}"
    echo -e "   • Service User: ${YELLOW}$SERVICE_USER${NC}"
    echo -e "   • Web Interface: ${YELLOW}http://$MAIN_SERVER_IP:8080${NC}"
    echo -e "   • Log File: ${YELLOW}$LOG_FILE${NC}"
    echo
    echo -e "${CYAN}🎮 Management Commands:${NC}"
    echo -e "   • Start service: ${YELLOW}nuclei-start${NC} or ${YELLOW}systemctl start nuclei-distributed${NC}"
    echo -e "   • Stop service: ${YELLOW}nuclei-stop${NC} or ${YELLOW}systemctl stop nuclei-distributed${NC}"
    echo -e "   • View status: ${YELLOW}nuclei-status${NC}"
    echo -e "   • View logs: ${YELLOW}nuclei-logs${NC}"
    echo -e "   • Cleanup droplets: ${YELLOW}nuclei-cleanup${NC}"
    echo
    echo -e "${CYAN}📊 Next Steps:${NC}"
    echo -e "   1. Open ${YELLOW}http://$MAIN_SERVER_IP:8080${NC} in your browser"
    echo -e "   2. Paste your target domains (one per line)"
    echo -e "   3. Choose number of droplets (auto-optimized)"
    echo -e "   4. Click '🚀 Start Scan' to begin"
    echo -e "   5. Monitor real-time progress and download results"
    echo
    echo -e "${CYAN}🔧 Configuration Files:${NC}"
    echo -e "   • Environment: ${YELLOW}$INSTALL_DIR/.env${NC}"
    echo -e "   • Docker Compose: ${YELLOW}$INSTALL_DIR/docker/docker-compose.prod.yml${NC}"
    echo -e "   • Service: ${YELLOW}/etc/systemd/system/nuclei-distributed.service${NC}"
    echo
    echo -e "${GREEN}Happy Scanning! 🔍🎯${NC}"
    echo
}

# Cleanup function for error handling
cleanup() {
    if [[ $? -ne 0 ]]; then
        error "Installation failed. Check $LOG_FILE for details."
        echo -e "${YELLOW}You can retry the installation or report issues at:${NC}"
        echo -e "${YELLOW}https://github.com/your-username/nuclei-distributed/issues${NC}"
    fi
}

# Main installation function
main() {
    trap cleanup EXIT
    
    print_banner
    check_root
    detect_os
    get_external_ip
    update_system
    install_docker
    install_docker_compose
    create_service_user
    setup_project_directory
    configure_firewall
    get_user_input
    generate_environment
    create_systemd_service
    create_management_scripts
    start_application
    health_check
    print_summary
}

# Run main function
main "$@"
