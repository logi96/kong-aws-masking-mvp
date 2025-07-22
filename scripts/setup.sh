#!/bin/bash

# Kong AWS Masking MVP - Initial Environment Setup Script
# Infrastructure Team - Sets up development environment from scratch

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly ENV_FILE="$PROJECT_ROOT/.env"
readonly ENV_EXAMPLE="$PROJECT_ROOT/.env.example"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_separator() {
    echo -e "${BLUE}================================${NC}"
}

# Utility functions
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Command '$cmd' not found"
        return 1
    fi
    return 0
}

prompt_user() {
    local message="$1"
    local default_value="${2:-}"
    local user_input
    
    if [ -n "$default_value" ]; then
        echo -n -e "${YELLOW}$message [$default_value]:${NC} "
    else
        echo -n -e "${YELLOW}$message:${NC} "
    fi
    
    read -r user_input
    echo "${user_input:-$default_value}"
}

confirm_action() {
    local message="$1"
    local response
    
    while true; do
        echo -n -e "${YELLOW}$message (y/n):${NC} "
        read -r response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Setup functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local prerequisites=("docker" "docker-compose" "curl" "git")
    local missing=()
    local versions=()
    
    for cmd in "${prerequisites[@]}"; do
        if check_command "$cmd"; then
            case $cmd in
                "docker")
                    versions+=("Docker: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)")
                    ;;
                "docker-compose")
                    versions+=("Docker Compose: $(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)")
                    ;;
                "curl")
                    versions+=("curl: $(curl --version | head -n1 | cut -d' ' -f2)")
                    ;;
                "git")
                    versions+=("Git: $(git --version | cut -d' ' -f3)")
                    ;;
            esac
        else
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing prerequisites: ${missing[*]}"
        log_info "Please install the missing tools and run setup again"
        return 1
    fi
    
    log_success "All prerequisites are available:"
    for version in "${versions[@]}"; do
        log_info "  $version"
    done
    
    return 0
}

setup_environment_file() {
    log_info "Setting up environment configuration..."
    
    if [ -f "$ENV_FILE" ]; then
        if confirm_action "Environment file already exists. Overwrite?"; then
            cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
            log_info "Backed up existing .env file"
        else
            log_info "Keeping existing environment file"
            return 0
        fi
    fi
    
    if [ ! -f "$ENV_EXAMPLE" ]; then
        log_error ".env.example file not found"
        return 1
    fi
    
    # Copy template
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    log_success "Created .env file from template"
    
    # Prompt for required values
    log_info "Please provide required configuration values:"
    
    local anthropic_key
    anthropic_key=$(prompt_user "Anthropic API Key (starts with sk-ant-api03-)")
    if [ -n "$anthropic_key" ]; then
        sed -i.bak "s/sk-ant-api03-YOUR-KEY-HERE/$anthropic_key/" "$ENV_FILE"
        rm -f "$ENV_FILE.bak"
    fi
    
    local aws_region
    aws_region=$(prompt_user "AWS Region" "us-east-1")
    if [ -n "$aws_region" ]; then
        sed -i.bak "s/AWS_REGION=us-east-1/AWS_REGION=$aws_region/" "$ENV_FILE"
        rm -f "$ENV_FILE.bak"
    fi
    
    # Ask about AWS credentials
    if confirm_action "Do you want to configure AWS credentials in the .env file? (not recommended for production)"; then
        local aws_key_id
        aws_key_id=$(prompt_user "AWS Access Key ID")
        if [ -n "$aws_key_id" ]; then
            sed -i.bak "s/# AWS_ACCESS_KEY_ID=your-access-key-id/AWS_ACCESS_KEY_ID=$aws_key_id/" "$ENV_FILE"
            rm -f "$ENV_FILE.bak"
        fi
        
        local aws_secret_key
        aws_secret_key=$(prompt_user "AWS Secret Access Key")
        if [ -n "$aws_secret_key" ]; then
            sed -i.bak "s/# AWS_SECRET_ACCESS_KEY=your-secret-access-key/AWS_SECRET_ACCESS_KEY=$aws_secret_key/" "$ENV_FILE"
            rm -f "$ENV_FILE.bak"
        fi
    else
        log_info "AWS credentials will be loaded from default AWS CLI configuration"
        log_info "Make sure to run 'aws configure' or set up AWS profiles"
    fi
    
    log_success "Environment file configured successfully"
    return 0
}

create_directories() {
    log_info "Creating required directories..."
    
    local directories=(
        "logs/kong"
        "logs/backend"
        ".docker/volumes"
        "backend/tests"
        "tests"
    )
    
    cd "$PROJECT_ROOT"
    
    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    done
    
    log_success "Directory structure ready"
    return 0
}

validate_docker_setup() {
    log_info "Validating Docker setup..."
    
    cd "$PROJECT_ROOT"
    
    # Check if docker-compose.yml is valid
    if ! docker-compose config > /dev/null 2>&1; then
        log_error "docker-compose.yml is invalid"
        return 1
    fi
    
    # Check if we can connect to Docker daemon
    if ! docker info > /dev/null 2>&1; then
        log_error "Cannot connect to Docker daemon"
        log_info "Please make sure Docker is running"
        return 1
    fi
    
    log_success "Docker setup is valid"
    return 0
}

build_images() {
    log_info "Building Docker images..."
    
    cd "$PROJECT_ROOT"
    
    if confirm_action "Build Docker images now? This may take several minutes"; then
        if docker-compose build --parallel; then
            log_success "Docker images built successfully"
        else
            log_error "Failed to build Docker images"
            return 1
        fi
    else
        log_info "Skipping image build - you can run 'docker-compose build' later"
    fi
    
    return 0
}

setup_git_hooks() {
    log_info "Setting up Git hooks..."
    
    cd "$PROJECT_ROOT"
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_warning "Not in a Git repository - skipping Git hooks setup"
        return 0
    fi
    
    # Create pre-commit hook for linting
    local pre_commit_hook=".git/hooks/pre-commit"
    
    if [ ! -f "$pre_commit_hook" ] || confirm_action "Git pre-commit hook exists. Overwrite?"; then
        cat > "$pre_commit_hook" << 'EOF'
#!/bin/bash
# Pre-commit hook for Kong AWS Masking MVP

echo "Running pre-commit checks..."

# Run health check
if [ -f "./scripts/health-check.sh" ]; then
    echo "Running health check..."
    if ! ./scripts/health-check.sh; then
        echo "Health check failed - commit aborted"
        exit 1
    fi
fi

# Run linting if backend code changed
if git diff --cached --name-only | grep -q "^backend/"; then
    echo "Backend code changed, running linting..."
    if command -v docker-compose &> /dev/null; then
        if docker-compose exec -T backend npm run lint; then
            echo "Linting passed"
        else
            echo "Linting failed - please fix issues before committing"
            exit 1
        fi
    else
        echo "Warning: docker-compose not available, skipping lint check"
    fi
fi

echo "Pre-commit checks passed"
EOF
        chmod +x "$pre_commit_hook"
        log_success "Git pre-commit hook installed"
    fi
    
    return 0
}

print_next_steps() {
    log_separator
    log_success "Setup completed successfully!"
    log_separator
    
    log_info "Next steps:"
    echo "  1. Start the services:"
    echo "     docker-compose up -d"
    echo ""
    echo "  2. Run health check:"
    echo "     ./scripts/health-check.sh"
    echo ""
    echo "  3. Test the API:"
    echo "     curl http://localhost:3000/health"
    echo "     curl http://localhost:8001/status"
    echo ""
    echo "  4. View logs:"
    echo "     ./scripts/logs.sh"
    echo ""
    echo "  5. For development with hot reload:"
    echo "     docker-compose -f docker-compose.yml -f docker-compose.dev.yml up"
    echo ""
    
    log_info "Important files:"
    echo "  - Environment config: .env"
    echo "  - Infrastructure docs: README-INFRA.md"  
    echo "  - Health check: scripts/health-check.sh"
    echo "  - Docker config: docker-compose.yml"
    echo ""
    
    log_info "Useful commands:"
    echo "  - Reset environment: ./scripts/reset.sh"
    echo "  - View aggregated logs: ./scripts/logs.sh"
    echo "  - Run tests: ./scripts/test-infra.sh"
    
    log_separator
}

# Main execution
main() {
    log_info "Starting Kong AWS Masking MVP Environment Setup"
    log_info "Timestamp: $(date -Iseconds)"
    log_separator
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Run setup steps
    if ! check_prerequisites; then
        exit 1
    fi
    
    if ! setup_environment_file; then
        exit 1
    fi
    
    if ! create_directories; then
        exit 1
    fi
    
    if ! validate_docker_setup; then
        exit 1
    fi
    
    if ! build_images; then
        exit 1
    fi
    
    setup_git_hooks
    
    print_next_steps
}

# Handle script interruption
trap 'log_error "Setup interrupted"; exit 130' INT TERM

# Run main function
main "$@"