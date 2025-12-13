#!/usr/bin/env bash
# DDGo Project Setup Script
# Initializes the development environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Print header
print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                  DDGo DevOps Project Setup                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    # Required tools
    if ! command_exists docker; then
        missing+=("docker")
    fi

    if ! command_exists docker-compose && ! docker compose version &> /dev/null; then
        missing+=("docker-compose")
    fi

    # Optional tools
    if ! command_exists terraform; then
        log_warning "Terraform not found - infrastructure deployment will not be available"
    fi

    if ! command_exists ansible; then
        log_warning "Ansible not found - configuration management will not be available"
    fi

    if ! command_exists python3; then
        missing+=("python3")
    fi

    if ! command_exists aws; then
        log_warning "AWS CLI not found - AWS deployment will not be available"
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Please install the missing tools:"
        echo "  Docker: https://docs.docker.com/get-docker/"
        echo "  Docker Compose: https://docs.docker.com/compose/install/"
        echo "  Python: https://www.python.org/downloads/"
        exit 1
    fi

    log_success "All required prerequisites are installed"
}

# Setup Python virtual environment
setup_python_env() {
    log_info "Setting up Python virtual environment..."

    if [ ! -d "venv" ]; then
        python3 -m venv venv
        log_success "Virtual environment created"
    else
        log_info "Virtual environment already exists"
    fi

    # Activate and install dependencies
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r app/requirements.txt

    log_success "Python dependencies installed"
}

# Create necessary directories
create_directories() {
    log_info "Creating necessary directories..."

    mkdir -p docker/nginx/ssl
    mkdir -p monitoring/alertmanager/templates
    mkdir -p logs
    mkdir -p data

    log_success "Directories created"
}

# Generate SSL certificates for local development
generate_ssl_certs() {
    log_info "Generating self-signed SSL certificates for local development..."

    local ssl_dir="docker/nginx/ssl"

    if [ -f "$ssl_dir/cert.pem" ] && [ -f "$ssl_dir/key.pem" ]; then
        log_info "SSL certificates already exist"
        return
    fi

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$ssl_dir/key.pem" \
        -out "$ssl_dir/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=DDGo/CN=localhost" \
        2>/dev/null

    log_success "SSL certificates generated"
}

# Create environment file
create_env_file() {
    log_info "Creating environment file..."

    if [ -f ".env" ]; then
        log_info ".env file already exists - skipping"
        return
    fi

    cat > .env << 'EOF'
# DDGo Environment Configuration
# Copy this file to .env and customize as needed

# Environment
ENVIRONMENT=development

# Application
APP_VERSION=1.0.0
PORT=5000

# Database
DB_HOST=postgres
DB_PORT=5432
DB_NAME=ddgo
DB_USER=ddgo
DB_PASSWORD=ddgo_dev_password

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Monitoring
GRAFANA_ADMIN_PASSWORD=admin

# AWS (for deployment)
AWS_REGION=us-east-1
AWS_PROFILE=default

# Slack (for alerts)
SLACK_WEBHOOK_URL=

# PagerDuty (for alerts)
PAGERDUTY_ROUTING_KEY=
EOF

    log_success ".env file created"
}

# Build Docker images
build_images() {
    log_info "Building Docker images..."

    cd docker
    docker compose build
    cd ..

    log_success "Docker images built"
}

# Start services
start_services() {
    log_info "Starting services..."

    cd docker
    docker compose up -d
    cd ..

    log_success "Services started"
}

# Wait for services to be healthy
wait_for_services() {
    log_info "Waiting for services to be healthy..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -sf http://localhost:5000/health > /dev/null 2>&1; then
            log_success "Application is healthy"
            return 0
        fi

        log_info "Waiting for application... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done

    log_error "Application failed to become healthy"
    return 1
}

# Print service URLs
print_service_urls() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    Service URLs                            ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║  Application:     http://localhost:5000                    ║"
    echo "║  Health Check:    http://localhost:5000/health             ║"
    echo "║  API Info:        http://localhost:5000/api/v1/info        ║"
    echo "║  Metrics:         http://localhost:5000/metrics            ║"
    echo "║  Prometheus:      http://localhost:9090                    ║"
    echo "║  Grafana:         http://localhost:3000 (admin/admin)      ║"
    echo "║  Alertmanager:    http://localhost:9093                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Main setup function
main() {
    print_header

    check_prerequisites
    create_directories
    create_env_file
    setup_python_env
    generate_ssl_certs
    build_images
    start_services
    wait_for_services
    print_service_urls

    log_success "Setup complete! The DDGo development environment is ready."
    echo ""
    echo "Next steps:"
    echo "  1. View the application at http://localhost:5000"
    echo "  2. View metrics in Grafana at http://localhost:3000"
    echo "  3. Run tests: cd app && pytest"
    echo "  4. Stop services: cd docker && docker compose down"
    echo ""
}

# Parse arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --check       Only check prerequisites"
        echo "  --build       Only build Docker images"
        echo "  --start       Only start services"
        echo "  --stop        Stop all services"
        exit 0
        ;;
    --check)
        check_prerequisites
        ;;
    --build)
        build_images
        ;;
    --start)
        start_services
        wait_for_services
        print_service_urls
        ;;
    --stop)
        log_info "Stopping services..."
        cd docker && docker compose down
        log_success "Services stopped"
        ;;
    *)
        main
        ;;
esac
