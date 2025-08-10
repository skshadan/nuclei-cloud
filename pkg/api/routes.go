package api

import (
	"github.com/gin-gonic/gin"
	"nuclei-distributed/pkg/orchestrator"
)

// SetupRoutes configures all API routes
func SetupRoutes(r *gin.Engine, orch *orchestrator.Orchestrator) {
	handler := NewHandler(orch)

	// Serve static files
	r.Static("/static", "./web/dist")
	r.StaticFile("/", "./web/dist/index.html")
	r.StaticFile("/favicon.ico", "./web/dist/favicon.ico")

	// API routes
	api := r.Group("/api")
	{
		// Scan management
		api.POST("/scan", handler.StartScan)
		api.GET("/scan/:scanId/status", handler.GetScanStatus)
		api.GET("/scan/:scanId/results", handler.GetResults)

		// Worker communication
		api.POST("/results/:scanId/:workerId", handler.ReceiveResults)
		api.POST("/heartbeat/:scanId/:workerId", handler.WorkerHeartbeat)
		api.POST("/complete/:scanId/:workerId", handler.CompleteWorker)
	}

	// WebSocket endpoint
	r.GET("/ws/:scanId", handler.HandleWebSocket)

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "healthy"})
	})
}
