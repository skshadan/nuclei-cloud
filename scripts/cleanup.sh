#!/bin/bash

# Cleanup script for Nuclei Distributed Scanner
# Removes old droplets and cleans up resources

set -e

# Configuration
DO_API_TOKEN="${DO_API_TOKEN}"
TAG_PREFIX="nuclei-worker"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-2}"  # Default: 2 hours

if [ -z "$DO_API_TOKEN" ]; then
    echo "ERROR: DO_API_TOKEN environment variable is required"
    exit 1
fi

echo "🧹 Starting cleanup of old Nuclei workers..."

# Function to get droplets by tag
get_droplets() {
    curl -s -X GET \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        "https://api.digitalocean.com/v2/droplets?tag_name=$TAG_PREFIX" | \
    jq -r '.droplets[]'
}

# Function to delete droplet
delete_droplet() {
    local droplet_id=$1
    local droplet_name=$2
    
    echo "🗑️  Deleting droplet: $droplet_name (ID: $droplet_id)"
    
    curl -s -X DELETE \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        "https://api.digitalocean.com/v2/droplets/$droplet_id"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully deleted droplet $droplet_name"
    else
        echo "❌ Failed to delete droplet $droplet_name"
    fi
}

# Get current timestamp
current_time=$(date +%s)

# Find and delete old droplets
echo "🔍 Searching for droplets older than $MAX_AGE_HOURS hours..."

get_droplets | jq -c '.' | while read -r droplet; do
    droplet_id=$(echo "$droplet" | jq -r '.id')
    droplet_name=$(echo "$droplet" | jq -r '.name')
    created_at=$(echo "$droplet" | jq -r '.created_at')
    
    # Convert created_at to timestamp
    created_timestamp=$(date -d "$created_at" +%s 2>/dev/null || echo 0)
    
    # Calculate age in hours
    age_seconds=$((current_time - created_timestamp))
    age_hours=$((age_seconds / 3600))
    
    echo "📊 Droplet: $droplet_name, Age: ${age_hours}h"
    
    if [ $age_hours -gt $MAX_AGE_HOURS ]; then
        echo "⏰ Droplet $droplet_name is older than $MAX_AGE_HOURS hours"
        delete_droplet "$droplet_id" "$droplet_name"
    else
        echo "✅ Droplet $droplet_name is still fresh"
    fi
done

echo "🎉 Cleanup completed!"

# Optional: Clean up orphaned volumes (if using)
echo "🔍 Checking for orphaned volumes..."

curl -s -X GET \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    "https://api.digitalocean.com/v2/volumes" | \
jq -r '.volumes[] | select(.droplet_ids | length == 0) | .id' | while read -r volume_id; do
    if [ -n "$volume_id" ]; then
        echo "🗑️  Found orphaned volume: $volume_id"
        # Uncomment to actually delete orphaned volumes
        # curl -s -X DELETE \
        #     -H "Authorization: Bearer $DO_API_TOKEN" \
        #     "https://api.digitalocean.com/v2/volumes/$volume_id"
    fi
done

echo "✨ All cleanup tasks completed!"
