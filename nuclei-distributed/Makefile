# Nuclei Distributed Scanner Makefile

.PHONY: help build run stop clean dev test lint docker-build docker-run setup

# Variables
PROJECT_NAME=nuclei-distributed
DOCKER_IMAGE=$(PROJECT_NAME):latest
COMPOSE_FILE=docker/docker-compose.yml
COMPOSE_PROD_FILE=docker/docker-compose.prod.yml

# Default target
help: ## Show this help message
	@echo "Nuclei Distributed Scanner - Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Set up the project (first time)
	@echo "🚀 Setting up Nuclei Distributed Scanner..."
	@if [ ! -f "env.example" ]; then echo "❌ env.example not found"; exit 1; fi
	@cp env.example .env
	@echo "✅ Environment file created (.env)"
	@echo "📝 Please edit .env file with your DigitalOcean API token"
	@echo "💡 Run 'make dev' to start development environment"

dev: ## Start development environment
	@echo "🔧 Starting development environment..."
	docker-compose -f $(COMPOSE_FILE) up --build

run: ## Start production environment
	@echo "🚀 Starting production environment..."
	docker-compose -f $(COMPOSE_PROD_FILE) up -d --build

stop: ## Stop all services
	@echo "⏹️  Stopping all services..."
	docker-compose -f $(COMPOSE_FILE) down
	docker-compose -f $(COMPOSE_PROD_FILE) down

restart: stop run ## Restart production environment

logs: ## View application logs
	docker-compose -f $(COMPOSE_FILE) logs -f app

build: ## Build the application
	@echo "🔨 Building application..."
	go build -o bin/$(PROJECT_NAME) ./cmd/main.go

build-web: ## Build web frontend
	@echo "🎨 Building web frontend..."
	cd web && npm install && npm run build

test: ## Run tests
	@echo "🧪 Running tests..."
	go test -v ./...

lint: ## Run linters
	@echo "🔍 Running linters..."
	golangci-lint run ./...

docker-build: ## Build Docker image
	@echo "🐳 Building Docker image..."
	docker build -f docker/Dockerfile.main -t $(DOCKER_IMAGE) .

docker-run: ## Run Docker container
	@echo "🐳 Running Docker container..."
	docker run -p 8080:8080 \
		-e DO_API_TOKEN=$(DO_API_TOKEN) \
		-e MAIN_SERVER_IP=$(MAIN_SERVER_IP) \
		$(DOCKER_IMAGE)

clean: ## Clean up resources
	@echo "🧹 Cleaning up..."
	docker-compose -f $(COMPOSE_FILE) down -v
	docker-compose -f $(COMPOSE_PROD_FILE) down -v
	docker system prune -f
	rm -rf bin/

clean-droplets: ## Clean up old DigitalOcean droplets
	@echo "🧹 Cleaning up old droplets..."
	@if [ -z "$(DO_API_TOKEN)" ]; then \
		echo "❌ DO_API_TOKEN not set"; \
		exit 1; \
	fi
	./scripts/cleanup.sh

deploy: ## Deploy to production server
	@echo "🚀 Deploying to production..."
	@if [ -z "$(SERVER)" ]; then \
		echo "❌ SERVER variable not set. Usage: make deploy SERVER=user@server"; \
		exit 1; \
	fi
	rsync -av --exclude='.git' --exclude='node_modules' . $(SERVER):/opt/nuclei-distributed/
	ssh $(SERVER) 'cd /opt/nuclei-distributed && make run'

health: ## Check application health
	@echo "🏥 Checking application health..."
	@curl -f http://localhost:8080/health || echo "❌ Application not healthy"

status: ## Show status of all services
	@echo "📊 Service status:"
	docker-compose -f $(COMPOSE_FILE) ps

backup: ## Backup scan results
	@echo "💾 Backing up scan results..."
	docker exec -t nuclei-distributed_redis_1 redis-cli --rdb /data/backup.rdb
	docker cp nuclei-distributed_redis_1:/data/backup.rdb ./backup-$(shell date +%Y%m%d-%H%M%S).rdb

install-deps: ## Install development dependencies
	@echo "📦 Installing dependencies..."
	go mod download
	cd web && npm install

update: ## Update dependencies
	@echo "⬆️  Updating dependencies..."
	go get -u ./...
	go mod tidy
	cd web && npm update

# Quick commands
start: run ## Alias for run
dev-logs: ## Show development logs
	docker-compose -f $(COMPOSE_FILE) logs -f

prod-logs: ## Show production logs  
	docker-compose -f $(COMPOSE_PROD_FILE) logs -f

# Development helpers
dev-backend: ## Run only backend in development
	go run cmd/main.go

dev-frontend: ## Run only frontend in development
	cd web && npm start

dev-redis: ## Run only Redis for development
	docker run -p 6379:6379 redis:7-alpine

# Security
security-scan: ## Run security scan on containers
	@echo "🔒 Running security scan..."
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy image $(DOCKER_IMAGE)

# Documentation
docs: ## Generate documentation
	@echo "📚 Generating documentation..."
	godoc -http=:6060 &
	@echo "Documentation available at http://localhost:6060"

# Benchmark
benchmark: ## Run performance benchmarks
	@echo "⚡ Running benchmarks..."
	go test -bench=. -benchmem ./...
