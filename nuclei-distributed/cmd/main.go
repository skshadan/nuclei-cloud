package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"nuclei-distributed/pkg/api"
	"nuclei-distributed/pkg/orchestrator"
)

func main() {
	log.Println("Starting Nuclei Distributed Scanner...")

	// Get configuration from environment
	doToken := os.Getenv("DO_API_TOKEN")
	if doToken == "" {
		log.Fatal("DO_API_TOKEN environment variable is required")
	}

	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		redisURL = "localhost:6379"
	}

	mainServerIP := os.Getenv("MAIN_SERVER_IP")
	if mainServerIP == "" {
		// Try to detect external IP or use localhost
		mainServerIP = "localhost"
		log.Printf("MAIN_SERVER_IP not set, using %s", mainServerIP)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Initialize orchestrator
	orch := orchestrator.New(doToken, redisURL, mainServerIP)
	log.Println("Orchestrator initialized")

	// Setup Gin router
	r := gin.Default()

	// Add CORS middleware
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization")
		
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		
		c.Next()
	})

	// Setup routes
	api.SetupRoutes(r, orch)

	log.Printf("Server starting on port %s", port)
	log.Printf("Access the UI at: http://localhost:%s", port)
	
	if err := r.Run(":" + port); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}
