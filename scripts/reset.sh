#!/bin/bash

# Kong AWS Masking MVP - Environment Reset Script
# Infrastructure Team - Completely resets the development environment

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

force_confirm() {
    local message="$1"
    log_warning "$message"
    echo -n -e "${RED}Type 'RESET' to confirm (or anything else to cancel):${NC} "
    local response
    read -r response
    
    if [ "$response" = "RESET" ]; then
        return 0
    else
        return 1
    fi
}

# Reset functions
stop_services() {
    log_info "Stopping all services..."
    
    cd "$PROJECT_ROOT"
    
    if docker-compose ps -q | grep -q .; then
        if docker-compose down; then
            log_success "Services stopped successfully"
        else
            log_warning "Some services may not have stopped cleanly"
        fi
    else
        log_info "No running services found"
    fi
    
    return 0
}

remove_containers() {
    log_info "Removing containers..."
    
    cd "$PROJECT_ROOT"
    
    # Remove containers with force
    if docker-compose down --remove-orphans; then
        log_success "Containers removed successfully"
    else
        log_warning "Some containers may not have been removed cleanly"
    fi
    
    # Remove any dangling containers related to the project
    local project_name
    project_name=$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
    
    local containers
    containers=$(docker ps -a --filter "name=$project_name" -q)
    
    if [ -n "$containers" ]; then
        log_info "Removing project-related containers..."
        if docker rm -f $containers; then
            log_success "Additional containers removed"
        else
            log_warning "Some additional containers could not be removed"
        fi
    fi
    
    return 0
}

remove_images() {
    if confirm_action "Remove Docker images? This will require rebuilding"; then
        log_info "Removing Docker images..."
        
        cd "$PROJECT_ROOT"
        
        # Remove images built by docker-compose
        if docker-compose down --rmi all --remove-orphans; then
            log_success "Images removed successfully"
        else
            log_warning "Some images may not have been removed"
        fi
        
        # Clean up dangling images
        local dangling_images
        dangling_images=$(docker images -f "dangling=true" -q)
        
        if [ -n "$dangling_images" ]; then
            log_info "Removing dangling images..."
            if docker rmi $dangling_images; then
                log_success "Dangling images removed"
            else
                log_warning "Some dangling images could not be removed"
            fi
        fi
    else
        log_info "Keeping Docker images"
    fi
    
    return 0
}

remove_volumes() {
    if confirm_action "Remove Docker volumes? This will delete all persistent data"; then
        log_info "Removing Docker volumes..."
        
        cd "$PROJECT_ROOT"
        
        # Remove named volumes
        if docker-compose down -v --remove-orphans; then
            log_success "Named volumes removed"
        else
            log_warning "Some volumes may not have been removed"
        fi
        
        # Remove local volume directories
        if [ -d ".docker/volumes" ]; then
            log_info "Removing local volume data..."
            if rm -rf .docker/volumes/*; then
                log_success "Local volume data removed"
            else
                log_warning "Some local volume data may remain"
            fi
        fi
    else
        log_info "Keeping Docker volumes"
    fi
    
    return 0
}

clean_logs() {
    if confirm_action "Remove log files?"; then
        log_info "Removing log files..."
        
        cd "$PROJECT_ROOT"
        
        # Remove log directories
        local log_dirs=("logs/kong" "logs/backend")
        
        for log_dir in "${log_dirs[@]}"; do
            if [ -d "$log_dir" ]; then
                if rm -rf "${log_dir:?}"/*; then
                    log_success "Cleaned $log_dir"
                else
                    log_warning "Could not clean $log_dir"
                fi
            fi
        done
        
        # Recreate empty log directories
        mkdir -p logs/kong logs/backend
        log_success "Log directories recreated"
    else
        log_info "Keeping log files"
    fi
    
    return 0
}

clean_dependencies() {
    if confirm_action "Remove node_modules and package locks?"; then
        log_info "Removing Node.js dependencies..."
        
        cd "$PROJECT_ROOT"
        
        # Remove backend dependencies
        if [ -d "backend/node_modules" ]; then
            if rm -rf backend/node_modules; then
                log_success "Removed backend/node_modules"
            else
                log_warning "Could not remove backend/node_modules"
            fi
        fi
        
        # Remove package locks
        local lock_files=("backend/package-lock.json" "backend/yarn.lock")
        
        for lock_file in "${lock_files[@]}"; do
            if [ -f "$lock_file" ]; then
                if rm -f "$lock_file"; then
                    log_success "Removed $lock_file"
                else
                    log_warning "Could not remove $lock_file"
                fi
            fi
        done
    else
        log_info "Keeping Node.js dependencies"
    fi
    
    return 0
}

reset_environment() {
    if confirm_action "Reset environment configuration (.env file)?"; then
        log_info "Resetting environment configuration..."
        
        cd "$PROJECT_ROOT"
        
        if [ -f ".env" ]; then
            # Backup existing .env
            local backup_name=".env.backup.$(date +%Y%m%d_%H%M%S)"
            if cp ".env" "$backup_name"; then
                log_info "Backed up .env to $backup_name"
            fi
            
            # Remove current .env
            if rm -f ".env"; then
                log_success "Environment file removed"
            else
                log_warning "Could not remove .env file"
            fi
        fi
        
        log_info "Run './scripts/setup.sh' to recreate environment configuration"
    else
        log_info "Keeping environment configuration"
    fi
    
    return 0
}

clean_docker_system() {
    if confirm_action "Run Docker system cleanup? (removes unused containers, networks, images)"; then
        log_info "Running Docker system cleanup..."
        
        # Clean up Docker system
        if docker system prune -a -f; then
            log_success "Docker system cleaned up"
        else
            log_warning "Docker system cleanup may not have completed successfully"
        fi
        
        # Clean up networks
        if docker network prune -f; then
            log_success "Unused networks removed"
        else
            log_warning "Network cleanup may not have completed successfully"
        fi
    else
        log_info "Skipping Docker system cleanup"
    fi
    
    return 0
}

# Reset modes
reset_soft() {
    log_info "Performing soft reset (stop services, keep data)..."
    stop_services
    clean_logs
    log_success "Soft reset completed"
}

reset_medium() {
    log_info "Performing medium reset (remove containers, keep images and volumes)..."
    stop_services
    remove_containers
    clean_logs
    clean_dependencies
    log_success "Medium reset completed"
}

reset_hard() {
    log_info "Performing hard reset (remove everything, keep environment config)..."
    stop_services
    remove_containers
    remove_images
    remove_volumes
    clean_logs
    clean_dependencies
    clean_docker_system
    log_success "Hard reset completed"
}

reset_nuclear() {
    if force_confirm "NUCLEAR RESET: This will remove EVERYTHING including environment config!"; then
        log_info "Performing nuclear reset (remove absolutely everything)..."
        stop_services
        remove_containers
        remove_images
        remove_volumes
        clean_logs
        clean_dependencies
        reset_environment
        clean_docker_system
        log_success "Nuclear reset completed"
        log_info "Run './scripts/setup.sh' to reinitialize the environment"
    else
        log_info "Nuclear reset cancelled"
        return 1
    fi
}

print_usage() {
    echo "Usage: $0 [mode]"
    echo ""
    echo "Reset modes:"
    echo "  soft     - Stop services, clean logs (keep everything else)"
    echo "  medium   - Remove containers, clean logs and dependencies"
    echo "  hard     - Remove containers, images, volumes, logs, dependencies"
    echo "  nuclear  - Remove EVERYTHING including environment config"
    echo "  help     - Show this help message"
    echo ""
    echo "If no mode is specified, interactive mode will be used."
}

# Interactive mode
interactive_reset() {
    log_info "Interactive Reset Mode"
    log_separator
    
    echo "Available reset options:"
    echo "  1. Soft Reset - Stop services, clean logs"
    echo "  2. Medium Reset - Remove containers, clean logs and dependencies"
    echo "  3. Hard Reset - Remove containers, images, volumes, logs, dependencies"
    echo "  4. Nuclear Reset - Remove EVERYTHING including environment config"
    echo "  5. Custom Reset - Choose specific components to reset"
    echo "  6. Cancel"
    echo ""
    
    while true; do
        echo -n -e "${YELLOW}Choose an option (1-6):${NC} "
        read -r choice
        
        case $choice in
            1)
                reset_soft
                break
                ;;
            2)
                reset_medium
                break
                ;;
            3)
                reset_hard
                break
                ;;
            4)
                reset_nuclear
                break
                ;;
            5)
                custom_reset
                break
                ;;
            6)
                log_info "Reset cancelled"
                exit 0
                ;;
            *)
                echo "Invalid option. Please choose 1-6."
                ;;
        esac
    done
}

custom_reset() {
    log_info "Custom Reset - Choose components to reset:"
    
    stop_services
    
    remove_containers
    remove_images
    remove_volumes
    clean_logs
    clean_dependencies
    reset_environment
    clean_docker_system
    
    log_success "Custom reset completed"
}

# Main execution
main() {
    log_info "Kong AWS Masking MVP - Environment Reset"
    log_info "Timestamp: $(date -Iseconds)"
    log_separator
    
    cd "$PROJECT_ROOT"
    
    # Parse command line arguments
    case "${1:-}" in
        "soft")
            reset_soft
            ;;
        "medium")
            reset_medium
            ;;
        "hard")
            reset_hard
            ;;
        "nuclear")
            reset_nuclear
            ;;
        "help"|"-h"|"--help")
            print_usage
            exit 0
            ;;
        "")
            interactive_reset
            ;;
        *)
            log_error "Unknown reset mode: $1"
            print_usage
            exit 1
            ;;
    esac
    
    log_separator
    log_info "Reset operation completed"
    log_info "You may want to run './scripts/setup.sh' to reinitialize your environment"
}

# Handle script interruption
trap 'log_error "Reset interrupted"; exit 130' INT TERM

# Run main function
main "$@"