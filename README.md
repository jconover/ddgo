# DDGo Infrastructure Platform

A comprehensive DevOps portfolio project demonstrating production-ready infrastructure, containerization, CI/CD pipelines, and monitoring capabilities.

## 🎯 Project Overview

This project showcases skills required for a Senior CloudOps Engineer role:

| Technology | Implementation |
|------------|----------------|
| **Infrastructure as Code** | Terraform modules for AWS (VPC, ECS, RDS, ALB) + Azure examples |
| **Containerization** | Multi-stage Docker builds, Docker Compose |
| **Configuration Management** | Ansible roles for server provisioning |
| **CI/CD** | GitHub Actions pipelines for testing, building, and deployment |
| **Monitoring** | Prometheus, Grafana, Alertmanager |
| **Programming** | Python Flask API, automation scripts |
| **Reverse Proxy** | Nginx with security hardening |

## 📁 Project Structure

```
ddgo/
├── app/                    # Python Flask API application
│   ├── src/               # Application source code
│   ├── tests/             # Unit tests
│   └── requirements.txt   # Python dependencies
├── docker/                 # Docker configurations
│   ├── Dockerfile         # Multi-stage build
│   ├── docker-compose.yml # Local development stack
│   └── nginx/             # Nginx configuration
├── terraform/              # Infrastructure as Code
│   ├── modules/           # Reusable Terraform modules
│   │   ├── vpc/          # VPC, subnets, NAT gateways
│   │   ├── ecs/          # ECS Fargate cluster and service
│   │   ├── alb/          # Application Load Balancer
│   │   └── rds/          # PostgreSQL database
│   ├── environments/      # Environment-specific configs
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── azure/             # Azure deployment example
├── ansible/                # Configuration management
│   ├── roles/             # Ansible roles
│   ├── playbooks/         # Deployment playbooks
│   └── inventories/       # Environment inventories
├── .github/workflows/      # CI/CD pipelines
│   ├── ci.yml             # Continuous Integration
│   ├── cd.yml             # Continuous Deployment
│   └── terraform.yml      # Infrastructure pipeline
├── monitoring/             # Observability stack
│   ├── prometheus/        # Metrics collection
│   ├── grafana/           # Dashboards
│   └── alertmanager/      # Alert routing
├── scripts/                # Automation scripts
│   ├── setup.sh           # Development setup
│   └── deploy.py          # Deployment automation
└── docs/                   # Documentation
```

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose
- Python 3.12+
- (Optional) Terraform 1.6+
- (Optional) Ansible 2.15+
- (Optional) AWS CLI v2

### Local Development

```bash
# Clone the repository
git clone <repository-url>
cd ddgo

# Run the setup script
./scripts/setup.sh

# Or manually with Docker Compose
cd docker
docker compose up -d
```

### Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | http://localhost:5000 | - |
| Health Check | http://localhost:5000/health | - |
| API Info | http://localhost:5000/api/v1/info | - |
| Prometheus | http://localhost:9090 | - |
| Grafana | http://localhost:3000 | admin/admin |
| Alertmanager | http://localhost:9093 | - |

## 🏗️ Infrastructure

### AWS Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Cloud                               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                         VPC                                │  │
│  │  ┌─────────────────┐  ┌─────────────────┐                │  │
│  │  │  Public Subnet  │  │  Public Subnet  │                │  │
│  │  │  ┌───────────┐  │  │  ┌───────────┐  │                │  │
│  │  │  │    ALB    │  │  │  │  NAT GW   │  │                │  │
│  │  │  └───────────┘  │  │  └───────────┘  │                │  │
│  │  └─────────────────┘  └─────────────────┘                │  │
│  │  ┌─────────────────┐  ┌─────────────────┐                │  │
│  │  │ Private Subnet  │  │ Private Subnet  │                │  │
│  │  │  ┌───────────┐  │  │  ┌───────────┐  │                │  │
│  │  │  │ECS Fargate│  │  │  │ECS Fargate│  │                │  │
│  │  │  └───────────┘  │  │  └───────────┘  │                │  │
│  │  └─────────────────┘  └─────────────────┘                │  │
│  │  ┌─────────────────┐  ┌─────────────────┐                │  │
│  │  │Database Subnet  │  │Database Subnet  │                │  │
│  │  │  ┌───────────┐  │  │  ┌───────────┐  │                │  │
│  │  │  │    RDS    │──┼──┼─▶│  Standby  │  │                │  │
│  │  │  └───────────┘  │  │  └───────────┘  │                │  │
│  │  └─────────────────┘  └─────────────────┘                │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Deploy Infrastructure

```bash
# Initialize and deploy to dev environment
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

## 📦 Application

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Basic health check |
| `/health/ready` | GET | Readiness probe (checks DB, Redis) |
| `/health/live` | GET | Liveness probe |
| `/metrics` | GET | Prometheus metrics |
| `/api/v1/info` | GET | Application information |
| `/api/v1/search` | POST | Sample search endpoint |

### Running Tests

```bash
cd app
pip install -r requirements.txt
pytest tests/ -v --cov=src
```

## 🔄 CI/CD Pipeline

### Continuous Integration (on push/PR)

1. **Lint & Static Analysis** - Black, Flake8, Bandit
2. **Unit Tests** - pytest with coverage
3. **Docker Build** - Multi-stage build with Trivy scanning
4. **Terraform Validate** - Format and validation checks
5. **Integration Tests** - Full stack testing with Docker Compose

### Continuous Deployment (on merge to main)

1. Build and push Docker image to ECR
2. Update ECS task definition
3. Deploy with rolling update
4. Verify deployment health
5. Send notifications

## 📊 Monitoring

### Metrics Collected

- Request rate, latency, error rate
- Resource utilization (CPU, memory, disk)
- Database connections and query performance
- Redis hit rate and memory usage
- Container health and restart counts

### Alert Rules

| Alert | Severity | Threshold |
|-------|----------|-----------|
| HighRequestLatency | Warning | P95 > 500ms for 5m |
| HighErrorRate | Critical | >5% 5xx errors for 5m |
| ApplicationDown | Critical | Instance unreachable for 1m |
| HighCPUUsage | Warning | >80% for 5m |
| DiskSpaceLow | Warning | <15% available |
| SLOAvailabilityBreach | Critical | <99.9% uptime |

## 🛠️ Configuration Management

### Ansible Roles

- **common** - Base system configuration, security hardening
- **docker** - Docker CE installation and configuration
- **nginx** - Reverse proxy with SSL
- **monitoring** - Node exporter, Prometheus setup

### Running Playbooks

```bash
cd ansible

# Deploy to development
ansible-playbook playbooks/site.yml -i inventories/dev/hosts.yml

# Deploy application only
ansible-playbook playbooks/deploy.yml -e "app_image=ddgo-api:latest"
```

## 📝 Runbooks

See the [docs/runbooks/](docs/runbooks/) directory for operational procedures:

- [Incident Response](docs/runbooks/incident-response.md)
- [Database Operations](docs/runbooks/database-operations.md)
- [Scaling Procedures](docs/runbooks/scaling.md)
- [Disaster Recovery](docs/runbooks/disaster-recovery.md)

## 🔐 Security

- Multi-stage Docker builds with non-root user
- VPC with public/private subnet segregation
- Security groups with least-privilege access
- SSL/TLS encryption in transit
- Secrets management via AWS Secrets Manager
- SSH hardening with key-only authentication
- Container vulnerability scanning with Trivy
- Infrastructure security scanning with tfsec

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and linting
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

Built as a DevOps portfolio project demonstrating CloudOps/Infrastructure Engineering skills.
