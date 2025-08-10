#!/bin/bash

echo "🔄 Force restarting Nuclei Distributed Scanner..."

# Stop all containers
echo "⏹️ Stopping containers..."
docker-compose -f docker/docker-compose.simple.yml down

# Remove all related images to force rebuild
echo "🗑️ Removing old images..."
docker rmi $(docker images | grep "docker-web" | awk '{print $3}') 2>/dev/null || true
docker rmi $(docker images | grep "nginx" | awk '{print $3}') 2>/dev/null || true

# Remove any volumes
echo "🧹 Cleaning volumes..."
docker volume prune -f

# Clear build cache
echo "🧹 Clearing build cache..."
docker builder prune -f

# Rebuild and start with no cache
echo "🚀 Rebuilding and starting (no cache)..."
docker-compose -f docker/docker-compose.simple.yml build --no-cache
docker-compose -f docker/docker-compose.simple.yml up -d

echo "✅ Force restart complete!"
echo "🌐 Check: http://139.59.26.176:8080"

# Wait a bit and check status
sleep 5
echo ""
echo "📊 Container Status:"
docker-compose -f docker/docker-compose.simple.yml ps
