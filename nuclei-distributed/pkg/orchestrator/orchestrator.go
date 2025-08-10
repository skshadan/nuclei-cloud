package orchestrator

import (
	"context"
	"encoding/base64"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/digitalocean/godo"
	"github.com/go-redis/redis/v8"
	"github.com/google/uuid"
	"nuclei-distributed/pkg/types"
)

type Orchestrator struct {
	doClient    *godo.Client
	redis       *redis.Client
	activeScans map[string]*types.ScanStatus
	mutex       sync.RWMutex
	mainServerIP string
}

func New(doToken string, redisURL string, mainServerIP string) *Orchestrator {
	return &Orchestrator{
		doClient:     godo.NewFromToken(doToken),
		redis:        redis.NewClient(&redis.Options{Addr: redisURL}),
		activeScans:  make(map[string]*types.ScanStatus),
		mainServerIP: mainServerIP,
	}
}

func (o *Orchestrator) StartScan(ctx context.Context, req *types.ScanRequest) error {
	log.Printf("Starting scan for %d domains with %d droplets", len(req.Domains), req.Droplets)
	
	// Generate scan ID if not provided
	if req.ID == "" {
		req.ID = uuid.New().String()
	}

	// Optimize droplet distribution
	optimizer := NewScanOptimizer()
	numDroplets, chunks := optimizer.OptimizeDistribution(req.Domains, req.Droplets)
	
	log.Printf("Optimized to %d droplets", numDroplets)

	// Initialize scan status
	o.mutex.Lock()
	o.activeScans[req.ID] = &types.ScanStatus{
		ID:             req.ID,
		Progress:       0,
		ActiveDroplets: make([]*types.WorkerStatus, 0),
		Results:        make([]types.ScanResult, 0),
		TotalDomains:   len(req.Domains),
		Status:         "starting",
	}
	o.mutex.Unlock()

	// Create droplets for each chunk
	for i, chunk := range chunks {
		go func(index int, domains []string) {
			if err := o.createAndStartWorker(ctx, req.ID, index, domains); err != nil {
				log.Printf("Failed to create worker %d: %v", index, err)
			}
		}(i, chunk)
	}

	return nil
}

func (o *Orchestrator) createAndStartWorker(ctx context.Context, scanID string, index int, domains []string) error {
	workerID := fmt.Sprintf("%s-worker-%d", scanID[:8], index)
	
	log.Printf("Creating worker %s with %d domains", workerID, len(domains))

	// Create user data script
	userData := o.generateUserData(scanID, workerID, domains)

	createRequest := &godo.DropletCreateRequest{
		Name:   workerID,
		Region: "nyc3",
		Size:   "s-1vcpu-1gb", 
		Image: godo.DropletCreateImage{
			Slug: "ubuntu-20-04-x64",
		},
		UserData: userData,
		Tags:     []string{"nuclei-worker", scanID},
	}

	droplet, _, err := o.doClient.Droplets.Create(ctx, createRequest)
	if err != nil {
		return fmt.Errorf("failed to create droplet: %v", err)
	}

	log.Printf("Created droplet %d for worker %s", droplet.ID, workerID)

	// Wait for droplet to get IP and be ready
	go o.waitForWorker(ctx, scanID, workerID, droplet.ID, len(domains))

	return nil
}

func (o *Orchestrator) waitForWorker(ctx context.Context, scanID, workerID string, dropletID int, totalDomains int) {
	// Wait for droplet to be ready and get IP
	for {
		droplet, _, err := o.doClient.Droplets.Get(ctx, dropletID)
		if err != nil {
			log.Printf("Error getting droplet status: %v", err)
			time.Sleep(5 * time.Second)
			continue
		}

		if droplet.Status == "active" {
			ip, err := droplet.PublicIPv4()
			if err == nil && ip != "" {
				// Add worker to active scan
				o.mutex.Lock()
				if scan, exists := o.activeScans[scanID]; exists {
					worker := &types.WorkerStatus{
						ID:           workerID,
						IP:           ip,
						Progress:     0,
						TotalDomains: totalDomains,
						CreatedAt:    time.Now(),
						Status:       "starting",
						Logs:         make([]types.Log, 0),
					}
					scan.ActiveDroplets = append(scan.ActiveDroplets, worker)
				}
				o.mutex.Unlock()
				
				log.Printf("Worker %s is ready at IP %s", workerID, ip)
				break
			}
		}

		time.Sleep(10 * time.Second)
	}
}

func (o *Orchestrator) generateUserData(scanID, workerID string, domains []string) string {
	domainsStr := strings.Join(domains, "\n")
	domainsB64 := base64.StdEncoding.EncodeToString([]byte(domainsStr))

	script := fmt.Sprintf(`#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Update system
apt-get update
apt-get install -y curl wget unzip

# Install Go
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Install nuclei
wget https://github.com/projectdiscovery/nuclei/releases/download/v3.0.4/nuclei_3.0.4_linux_amd64.zip
unzip nuclei_3.0.4_linux_amd64.zip
mv nuclei /usr/local/bin/

# Set up environment
export SCAN_ID=%s
export WORKER_ID=%s
export MAIN_SERVER=%s
export DOMAINS_B64=%s

# Decode domains
echo $DOMAINS_B64 | base64 -d > /root/domains.txt

# Download and run worker script
curl -L https://raw.githubusercontent.com/projectdiscovery/nuclei/main/nuclei-templates.tar.gz | tar -xzf - -C /root/

# Start scan
/usr/local/bin/nuclei -l /root/domains.txt -json -o /root/results.json &

# Monitor and send results
while true; do
    if [ -f /root/results.json ]; then
        tail -f /root/results.json | while read line; do
            curl -X POST \
                -H "Content-Type: application/json" \
                -d "$line" \
                "http://$MAIN_SERVER:8080/api/results/$SCAN_ID/$WORKER_ID" || true
        done
    fi
    sleep 5
done
`, scanID, workerID, o.mainServerIP, domainsB64)

	return script
}

func (o *Orchestrator) GetScanStatus(scanID string) (*types.ScanStatus, error) {
	o.mutex.RLock()
	defer o.mutex.RUnlock()
	
	if status, exists := o.activeScans[scanID]; exists {
		return status, nil
	}
	
	return nil, fmt.Errorf("scan not found")
}

func (o *Orchestrator) UpdateWorkerProgress(scanID, workerID string, progress float64, currentDomain string) {
	o.mutex.Lock()
	defer o.mutex.Unlock()
	
	if scan, exists := o.activeScans[scanID]; exists {
		for _, worker := range scan.ActiveDroplets {
			if worker.ID == workerID {
				worker.Progress = progress
				worker.CurrentDomain = currentDomain
				worker.DomainsScanned = int(float64(worker.TotalDomains) * progress / 100)
				break
			}
		}
		
		// Update overall progress
		totalProgress := 0.0
		for _, worker := range scan.ActiveDroplets {
			totalProgress += worker.Progress
		}
		if len(scan.ActiveDroplets) > 0 {
			scan.Progress = totalProgress / float64(len(scan.ActiveDroplets))
		}
	}
}

func (o *Orchestrator) AddResult(scanID string, result types.ScanResult) {
	o.mutex.Lock()
	defer o.mutex.Unlock()
	
	if scan, exists := o.activeScans[scanID]; exists {
		scan.Results = append(scan.Results, result)
		scan.ScannedDomains++
	}
}

func (o *Orchestrator) CleanupScan(scanID string) error {
	o.mutex.Lock()
	defer o.mutex.Unlock()
	
	if scan, exists := o.activeScans[scanID]; exists {
		// Destroy all droplets
		for _, worker := range scan.ActiveDroplets {
			// Find and destroy droplet by name
			droplets, _, err := o.doClient.Droplets.ListByTag(context.Background(), scanID, nil)
			if err == nil {
				for _, droplet := range droplets {
					if strings.Contains(droplet.Name, worker.ID) {
						o.doClient.Droplets.Delete(context.Background(), droplet.ID)
						log.Printf("Destroyed droplet %d for worker %s", droplet.ID, worker.ID)
					}
				}
			}
		}
		
		// Remove from active scans
		delete(o.activeScans, scanID)
	}
	
	return nil
}
