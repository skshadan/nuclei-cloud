#!/bin/bash

echo "🔄 Force restarting Nuclei Distributed Scanner..."

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
    echo "✅ Environment variables loaded"
else
    echo "⚠️  Warning: .env file not found"
fi

# Stop all containers
echo "⏹️ Stopping containers..."
docker-compose -f docker/docker-compose.full.yml down

# Remove all related images to force rebuild
echo "🗑️ Removing old images..."
docker rmi $(docker images | grep "nuclei-cloud" | awk '{print $3}') 2>/dev/null || true
docker rmi $(docker images | grep "docker-web" | awk '{print $3}') 2>/dev/null || true
docker rmi $(docker images | grep "nginx" | awk '{print $3}') 2>/dev/null || true

# Remove any volumes
echo "🧹 Cleaning volumes..."
docker volume prune -f

# Clear build cache
echo "🧹 Clearing build cache..."
docker builder prune -af

# Rebuild and start with no cache
echo "🚀 Rebuilding and starting (no cache)..."
docker-compose -f docker/docker-compose.full.yml build --no-cache
docker-compose -f docker/docker-compose.full.yml up -d

echo "✅ Force restart complete!"

# Wait for services and check health
echo "⏳ Waiting for services to start..."
sleep 15

echo "🔍 Checking service health..."
if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
    echo "✅ Services are healthy!"
    echo "🌐 Web UI: http://$(hostname -I | awk '{print $1}'):8080"
else
    echo "⚠️  Health check failed. Check logs below:"
fi

echo ""
echo "📊 Container Status:"
docker-compose -f docker/docker-compose.full.yml ps
