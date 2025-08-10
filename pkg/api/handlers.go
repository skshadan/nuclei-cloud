package api

import (
	"log"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"nuclei-distributed/pkg/orchestrator"
	"nuclei-distributed/pkg/types"
)

type Handler struct {
	orchestrator *orchestrator.Orchestrator
	wsManager    *WebSocketManager
}

func NewHandler(orch *orchestrator.Orchestrator) *Handler {
	return &Handler{
		orchestrator: orch,
		wsManager:    NewWebSocketManager(),
	}
}

// StartScan handles the scan start request
func (h *Handler) StartScan(c *gin.Context) {
	var req types.ScanRequest
	if err := c.BindJSON(&req); err != nil {
		log.Printf("Error binding request: %v", err)
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	if len(req.Domains) == 0 {
		c.JSON(400, gin.H{"error": "No domains provided"})
		return
	}

	// Clean and filter domains
	cleanDomains := make([]string, 0)
	for _, domain := range req.Domains {
		domain = strings.TrimSpace(domain)
		if domain != "" {
			cleanDomains = append(cleanDomains, domain)
		}
	}

	if len(cleanDomains) == 0 {
		c.JSON(400, gin.H{"error": "No valid domains provided"})
		return
	}

	// Generate scan ID
	req.ID = uuid.New().String()
	req.Domains = cleanDomains

	log.Printf("Starting scan %s with %d domains and %d droplets", req.ID, len(req.Domains), req.Droplets)

	// Start the scan
	if err := h.orchestrator.StartScan(c.Request.Context(), &req); err != nil {
		log.Printf("Error starting scan: %v", err)
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{
		"scan_id": req.ID,
		"message": "Scan started successfully",
		"domains_count": len(req.Domains),
	})
}

// GetScanStatus returns the current status of a scan
func (h *Handler) GetScanStatus(c *gin.Context) {
	scanID := c.Param("scanId")
	
	status, err := h.orchestrator.GetScanStatus(scanID)
	if err != nil {
		c.JSON(404, gin.H{"error": "Scan not found"})
		return
	}

	c.JSON(200, status)
}

// ReceiveResults handles results from worker droplets
func (h *Handler) ReceiveResults(c *gin.Context) {
	scanID := c.Param("scanId")
	workerID := c.Param("workerId")

	var result types.ScanResult
	if err := c.BindJSON(&result); err != nil {
		log.Printf("Error binding result: %v", err)
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// Set metadata
	result.Timestamp = time.Now()
	result.WorkerID = workerID

	// Add result to orchestrator
	h.orchestrator.AddResult(scanID, result)

	// Broadcast to WebSocket clients
	message := types.WebSocketMessage{
		Type: "new_result",
		Data: result,
	}
	h.wsManager.BroadcastToScan(scanID, message)

	log.Printf("Received result from %s: %s - %s", workerID, result.Host, result.Template)

	c.JSON(200, gin.H{"status": "received"})
}

// WorkerHeartbeat handles heartbeat from workers
func (h *Handler) WorkerHeartbeat(c *gin.Context) {
	scanID := c.Param("scanId")
	workerID := c.Param("workerId")

	var heartbeat struct {
		Progress      float64 `json:"progress"`
		CurrentDomain string  `json:"current_domain"`
		Message       string  `json:"message"`
	}

	if err := c.BindJSON(&heartbeat); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// Update worker progress
	h.orchestrator.UpdateWorkerProgress(scanID, workerID, heartbeat.Progress, heartbeat.CurrentDomain)

	// Broadcast status update
	status, _ := h.orchestrator.GetScanStatus(scanID)
	if status != nil {
		message := types.WebSocketMessage{
			Type: "status_update",
			Data: status,
		}
		h.wsManager.BroadcastToScan(scanID, message)
	}

	c.JSON(200, gin.H{"status": "updated"})
}

// CompleteWorker handles worker completion notification
func (h *Handler) CompleteWorker(c *gin.Context) {
	scanID := c.Param("scanId")
	workerID := c.Param("workerId")

	log.Printf("Worker %s completed for scan %s", workerID, scanID)

	// Update worker status to completed
	h.orchestrator.UpdateWorkerProgress(scanID, workerID, 100.0, "completed")

	// Check if all workers are complete
	status, err := h.orchestrator.GetScanStatus(scanID)
	if err == nil {
		allComplete := true
		for _, worker := range status.ActiveDroplets {
			if worker.Progress < 100.0 {
				allComplete = false
				break
			}
		}

		if allComplete {
			log.Printf("All workers completed for scan %s", scanID)
			status.Status = "completed"
			
			// Broadcast completion
			message := types.WebSocketMessage{
				Type: "scan_complete",
				Data: status,
			}
			h.wsManager.BroadcastToScan(scanID, message)

			// Schedule cleanup
			go func() {
				time.Sleep(30 * time.Second) // Wait 30 seconds before cleanup
				h.orchestrator.CleanupScan(scanID)
			}()
		}
	}

	c.JSON(200, gin.H{"status": "completed"})
}

// GetResults returns all results for a scan
func (h *Handler) GetResults(c *gin.Context) {
	scanID := c.Param("scanId")
	
	status, err := h.orchestrator.GetScanStatus(scanID)
	if err != nil {
		c.JSON(404, gin.H{"error": "Scan not found"})
		return
	}

	// Return results as JSON or CSV based on Accept header
	accept := c.GetHeader("Accept")
	if strings.Contains(accept, "text/csv") {
		c.Header("Content-Type", "text/csv")
		c.Header("Content-Disposition", "attachment; filename=scan_results.csv")
		
		// Write CSV headers
		c.String(200, "Host,Template,Severity,Match,Timestamp,WorkerID\n")
		
		// Write results
		for _, result := range status.Results {
			c.String(200, "%s,%s,%s,%s,%s,%s\n",
				result.Host,
				result.Template,
				result.Severity,
				result.Match,
				result.Timestamp.Format(time.RFC3339),
				result.WorkerID,
			)
		}
	} else {
		c.JSON(200, status.Results)
	}
}
