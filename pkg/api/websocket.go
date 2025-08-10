package api

import (
	"log"
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"nuclei-distributed/pkg/types"
)

type WebSocketManager struct {
	clients   map[string]map[*websocket.Conn]bool // scanID -> connections
	broadcast map[string]chan types.WebSocketMessage // scanID -> broadcast channel
	mutex     sync.RWMutex
	upgrader  websocket.Upgrader
}

func NewWebSocketManager() *WebSocketManager {
	return &WebSocketManager{
		clients:   make(map[string]map[*websocket.Conn]bool),
		broadcast: make(map[string]chan types.WebSocketMessage),
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins in development
			},
		},
	}
}

func (h *Handler) HandleWebSocket(c *gin.Context) {
	scanID := c.Param("scanId")
	
	conn, err := h.wsManager.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}
	defer conn.Close()

	// Register client
	h.wsManager.RegisterClient(scanID, conn)
	defer h.wsManager.UnregisterClient(scanID, conn)

	log.Printf("Client connected to scan %s", scanID)

	// Send current status immediately
	if status, err := h.orchestrator.GetScanStatus(scanID); err == nil {
		message := types.WebSocketMessage{
			Type: "status_update",
			Data: status,
		}
		conn.WriteJSON(message)
	}

	// Listen for client messages (ping/pong, etc.)
	for {
		var msg types.WebSocketMessage
		err := conn.ReadJSON(&msg)
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			break
		}

		// Handle client messages if needed
		switch msg.Type {
		case "ping":
			response := types.WebSocketMessage{
				Type: "pong",
				Data: "pong",
			}
			conn.WriteJSON(response)
		}
	}
}

func (wsm *WebSocketManager) RegisterClient(scanID string, conn *websocket.Conn) {
	wsm.mutex.Lock()
	defer wsm.mutex.Unlock()

	if wsm.clients[scanID] == nil {
		wsm.clients[scanID] = make(map[*websocket.Conn]bool)
		wsm.broadcast[scanID] = make(chan types.WebSocketMessage, 100)
		
		// Start broadcast goroutine for this scan
		go wsm.handleBroadcast(scanID)
	}

	wsm.clients[scanID][conn] = true
}

func (wsm *WebSocketManager) UnregisterClient(scanID string, conn *websocket.Conn) {
	wsm.mutex.Lock()
	defer wsm.mutex.Unlock()

	if clients, exists := wsm.clients[scanID]; exists {
		if _, exists := clients[conn]; exists {
			delete(clients, conn)
			
			// Clean up if no more clients
			if len(clients) == 0 {
				close(wsm.broadcast[scanID])
				delete(wsm.clients, scanID)
				delete(wsm.broadcast, scanID)
			}
		}
	}
}

func (wsm *WebSocketManager) BroadcastToScan(scanID string, message types.WebSocketMessage) {
	wsm.mutex.RLock()
	broadcastChan, exists := wsm.broadcast[scanID]
	wsm.mutex.RUnlock()

	if exists {
		select {
		case broadcastChan <- message:
		default:
			log.Printf("Broadcast channel full for scan %s", scanID)
		}
	}
}

func (wsm *WebSocketManager) handleBroadcast(scanID string) {
	broadcastChan := wsm.broadcast[scanID]
	
	for message := range broadcastChan {
		wsm.mutex.RLock()
		clients := wsm.clients[scanID]
		wsm.mutex.RUnlock()

		for conn := range clients {
			err := conn.WriteJSON(message)
			if err != nil {
				log.Printf("Error writing to WebSocket: %v", err)
				conn.Close()
				wsm.UnregisterClient(scanID, conn)
			}
		}
	}
}
