package types

import "time"

// ScanRequest represents a scan request from the frontend
type ScanRequest struct {
	ID       string   `json:"id"`
	Domains  []string `json:"domains"`
	Droplets int      `json:"droplets"`
	Status   string   `json:"status"`
}

// WorkerStatus represents the status of a worker droplet
type WorkerStatus struct {
	ID             string    `json:"id"`
	IP             string    `json:"ip"`
	Progress       float64   `json:"progress"`
	CurrentDomain  string    `json:"currentDomain"`
	DomainsScanned int       `json:"domainsScanned"`
	TotalDomains   int       `json:"totalDomains"`
	Logs           []Log     `json:"logs"`
	CreatedAt      time.Time `json:"createdAt"`
	Status         string    `json:"status"` // running, completed, failed
}

// Log represents a log entry from a worker
type Log struct {
	Timestamp time.Time `json:"timestamp"`
	Message   string    `json:"message"`
	Type      string    `json:"type"` // info, scan, error, success
	WorkerID  string    `json:"workerId"`
}

// ScanResult represents a nuclei scan result
type ScanResult struct {
	Host      string    `json:"host"`
	Template  string    `json:"template"`
	Severity  string    `json:"severity"`
	Match     string    `json:"match"`
	Timestamp time.Time `json:"timestamp"`
	WorkerID  string    `json:"workerId"`
}

// ScanStatus represents the overall status of a scan
type ScanStatus struct {
	ID             string          `json:"id"`
	Progress       float64         `json:"progress"`
	ActiveDroplets []*WorkerStatus `json:"activeDroplets"`
	Results        []ScanResult    `json:"results"`
	TotalDomains   int             `json:"totalDomains"`
	ScannedDomains int             `json:"scannedDomains"`
	Status         string          `json:"status"`
}

// DropletConfig represents configuration for creating droplets
type DropletConfig struct {
	Region string `json:"region"`
	Size   string `json:"size"`
	Image  string `json:"image"`
}

// WebSocketMessage represents messages sent via websocket
type WebSocketMessage struct {
	Type string      `json:"type"`
	Data interface{} `json:"data"`
}
