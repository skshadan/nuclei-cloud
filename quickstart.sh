#!/bin/bash

# 🚀 Nuclei Distributed Scanner - One-Line Quickstart
# This script downloads and runs the full installer

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🎯 Nuclei Distributed Scanner - Quickstart Installer${NC}"
echo -e "${YELLOW}This will download and install everything needed for distributed vulnerability scanning.${NC}"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}This script needs root privileges. Switching to sudo...${NC}"
    exec sudo "$0" "$@"
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo -e "${GREEN}📥 Downloading installation files...${NC}"

# Download the repository
curl -L https://github.com/skshadan/nuclei-cloud/archive/main.tar.gz -o nuclei-cloud.tar.gz
tar -xzf nuclei-cloud.tar.gz
cd nuclei-cloud-main/

# Make installer executable
chmod +x install.sh

echo -e "${GREEN}🚀 Starting installation...${NC}"
echo

# Run the main installer
./install.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo -e "${GREEN}✅ Quickstart installation complete!${NC}"
