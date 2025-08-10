# 🎯 Nuclei Distributed Scanner

A powerful distributed vulnerability scanner that runs Nuclei across multiple DigitalOcean droplets for high-speed, large-scale security assessments.

## ✨ Features

- **🚀 Distributed Scanning**: Automatically distributes domains across multiple DigitalOcean droplets
- **📊 Real-time Monitoring**: Live progress tracking and results streaming
- **🎨 Modern Web UI**: Clean, responsive interface with real-time updates
- **⚡ Auto-scaling**: Intelligent optimization of droplet count based on workload
- **💾 Export Results**: Download results in CSV format
- **🔧 Easy Deployment**: One-command Docker setup
- **🛡️ Security**: Built-in cleanup and resource management

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Web UI        │    │  API Server     │    │  Orchestrator   │
│                 │◄──►│                 │◄──►│                 │
│ • Domain Input  │    │ • REST API      │    │ • Droplet Mgmt  │
│ • Progress View │    │ • WebSocket     │    │ • Work Dist.    │
│ • Results       │    │ • Results Agg.  │    │ • Optimization  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                        ┌──────────────────────────────┼──────────────────────────────┐
                        │                              │                              │
                        ▼                              ▼                              ▼
              ┌─────────────────┐              ┌─────────────────┐              ┌─────────────────┐
              │ Worker Droplet 1│              │ Worker Droplet 2│              │ Worker Droplet N│
              │                 │              │                 │              │                 │
              │ • Nuclei Scan   │              │ • Nuclei Scan   │              │ • Nuclei Scan   │
              │ • Domain Chunk  │              │ • Domain Chunk  │              │ • Domain Chunk  │
              │ • Result Stream │              │ • Result Stream │              │ • Result Stream │
              └─────────────────┘              └─────────────────┘              └─────────────────┘
```

## 🚀 Quick Start

### ⚡ One-Command Installation

**The easiest way to get started:**

```bash
# Install everything automatically (Ubuntu/Debian/CentOS/RHEL)
curl -sSL https://raw.githubusercontent.com/your-username/nuclei-distributed/main/quickstart.sh | sudo bash
```

This single command will:
- ✅ Install Docker & Docker Compose
- ✅ Setup Redis with secure password
- ✅ Configure firewall rules
- ✅ Create service user & directories  
- ✅ Generate environment configuration
- ✅ Start the application
- ✅ Create management commands

### 📋 Manual Installation

If you prefer manual setup:

```bash
# 1. Clone the repository
git clone https://github.com/your-username/nuclei-distributed.git
cd nuclei-distributed

# 2. Run the installer
sudo ./install.sh
```

### 🎯 Prerequisites

The installer handles everything, but your server needs:
- **OS**: Ubuntu 18+, Debian 10+, CentOS 7+, RHEL 8+
- **RAM**: Minimum 1GB (2GB recommended)
- **Ports**: 8080 (auto-configured)
- **DigitalOcean API Token** (you'll be prompted)

### 🎮 Post-Installation Management

After installation, use these simple commands:

```bash
# Service management
nuclei-start          # Start the scanner
nuclei-stop           # Stop the scanner  
nuclei-status         # Check status
nuclei-logs           # View live logs
nuclei-cleanup        # Clean old droplets

# Or use systemd
systemctl start nuclei-distributed
systemctl stop nuclei-distributed
systemctl status nuclei-distributed
```

### 🌐 Access the Interface

Open your browser and navigate to:
- **Local**: http://localhost:8080  
- **Remote**: http://your-server-ip:8080

## 📖 Usage Guide

### Basic Scan

1. **Enter Domains**: Paste your target domains (one per line) in the text area
2. **Set Droplets**: Choose the number of droplets (1-10, auto-optimized)
3. **Start Scan**: Click "🚀 Start Scan" to begin
4. **Monitor Progress**: Watch real-time progress and results
5. **Export Results**: Download results as CSV when complete

### Example Domain List
```
example.com
test.com
target.org
subdomain.example.com
api.target.org
```

### Optimal Droplet Configuration

| Domains | Recommended Droplets | Scan Time* |
|---------|---------------------|------------|
| 1-100   | 2-3                 | 5-15 min   |
| 100-500 | 3-5                 | 15-30 min  |
| 500-1000| 5-7                 | 30-60 min  |
| 1000+   | 7-10                | 1-2 hours  |

*Approximate times vary based on target responsiveness and template count

## ⚙️ Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `DO_API_TOKEN` | DigitalOcean API token | - | ✅ |
| `MAIN_SERVER_IP` | External IP of main server | localhost | ⚠️  |
| `REDIS_URL` | Redis connection string | redis:6379 | ❌ |
| `PORT` | Application port | 8080 | ❌ |

### Droplet Configuration

Default droplet settings:
- **Region**: nyc3
- **Size**: s-1vcpu-1gb ($6/month, billed hourly)
- **Image**: ubuntu-20-04-x64
- **Auto-cleanup**: 30 seconds after completion

### Scan Optimization

The system automatically optimizes:
- **Max domains per droplet**: 500
- **Min domains per droplet**: 50
- **Max concurrent droplets**: 10
- **Nuclei rate limiting**: 10 requests/second per droplet

## 🔧 Advanced Usage

### Custom Templates

To use custom Nuclei templates:

```bash
# Mount custom templates directory
docker run -v /path/to/templates:/custom-templates nuclei-distributed
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `POST /api/scan` | POST | Start new scan |
| `GET /api/scan/:id/status` | GET | Get scan status |
| `GET /api/scan/:id/results` | GET | Download results |
| `GET /ws/:id` | WebSocket | Real-time updates |

### Cleanup Old Droplets

```bash
# Manual cleanup
./scripts/cleanup.sh

# Set max age (default: 2 hours)
MAX_AGE_HOURS=1 ./scripts/cleanup.sh
```

## 🛠️ Development

### Local Development

```bash
# Start dependencies
docker-compose up redis

# Run backend
go run cmd/main.go

# Run frontend (in separate terminal)
cd web
npm install
npm start
```

### Project Structure

```
nuclei-distributed/
├── cmd/                    # Application entry point
├── pkg/
│   ├── api/               # REST API handlers
│   ├── orchestrator/      # Droplet management
│   ├── worker/            # Worker node logic
│   └── types/             # Shared types
├── web/                   # React frontend
├── docker/                # Docker configurations
├── scripts/               # Utility scripts
└── README.md
```

### Adding New Features

1. **Backend**: Add handlers in `pkg/api/`
2. **Frontend**: Add components in `web/src/components/`
3. **Worker Logic**: Modify `scripts/worker-setup.sh`

## 🐛 Troubleshooting

### Common Issues

**❌ "DO_API_TOKEN is required"**
```bash
export DO_API_TOKEN="your_token_here"
```

**❌ Workers not connecting**
- Check MAIN_SERVER_IP is set to external IP
- Verify firewall allows port 8080
- Check DigitalOcean API token permissions

**❌ Scan gets stuck**
- Check worker logs in droplet console
- Verify domains are reachable
- Monitor rate limiting

### Debug Mode

```bash
# Enable debug logging
GIN_MODE=debug docker-compose up

# Access Redis for debugging
docker-compose --profile debug up redis-commander
# Open http://localhost:8081
```

### Logs

```bash
# Application logs
docker-compose logs -f app

# Worker logs (SSH to droplet)
ssh root@droplet_ip tail -f /var/log/nuclei-worker.log
```

## 💰 Cost Estimation

### DigitalOcean Pricing

| Droplets | Duration | Hourly Cost | Daily Cost |
|----------|----------|-------------|------------|
| 3        | 1 hour   | $0.027      | $0.65      |
| 5        | 2 hours  | $0.090      | $2.16      |
| 10       | 4 hours  | $0.360      | $8.64      |

**Note**: Droplets are automatically destroyed after scan completion.

## 🔒 Security Considerations

- **API Tokens**: Store securely, use environment variables
- **Network**: Consider VPC for production deployments  
- **Templates**: Only use trusted Nuclei templates
- **Results**: Ensure proper access controls on results
- **Cleanup**: Enable automatic droplet cleanup

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/your-username/nuclei-distributed/issues)
- **Documentation**: [Wiki](https://github.com/your-username/nuclei-distributed/wiki)
- **Community**: [Discussions](https://github.com/your-username/nuclei-distributed/discussions)

## 🙏 Acknowledgments

- [ProjectDiscovery](https://projectdiscovery.io/) for Nuclei
- [DigitalOcean](https://digitalocean.com/) for cloud infrastructure
- [Gin Framework](https://gin-gonic.com/) for the web framework
- [React](https://reactjs.org/) for the frontend

---

**⚡ Happy Scanning!** 

Built with ❤️ for the security community.
