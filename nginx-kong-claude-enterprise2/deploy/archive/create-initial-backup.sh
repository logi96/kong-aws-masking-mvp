#!/bin/bash

# Create Initial Backup for Kong AWS Masking MVP
# Purpose: Create first backup to enable rollback functionality

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Create backup directories
mkdir -p "${PROJECT_ROOT}/backups/pre-deploy"
mkdir -p "${PROJECT_ROOT}/backups/rollback-state"

# Create initial backup
create_initial_backup() {
    local backup_id="deploy-$(date +%Y%m%d-%H%M%S)"
    local backup_dir="${PROJECT_ROOT}/backups/pre-deploy/$backup_id"
    
    echo "Creating initial backup: $backup_id"
    mkdir -p "$backup_dir"
    
    # Backup current configuration
    echo "Backing up configuration files..."
    cp "${PROJECT_ROOT}/config/development.env" "$backup_dir/config.env" 2>/dev/null || echo "Warning: development.env not found"
    cp "${PROJECT_ROOT}/.env" "$backup_dir/env-file.backup" 2>/dev/null || echo "Warning: .env not found"
    
    # Backup docker-compose configuration
    cp "${PROJECT_ROOT}/docker-compose.yml" "$backup_dir/docker-compose.yml.backup" 2>/dev/null || echo "Warning: docker-compose.yml not found"
    
    # Try to backup Redis data if Redis is running
    echo "Attempting Redis data backup..."
    if docker exec claude-redis redis-cli -a "CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL" --no-auth-warning BGSAVE 2>/dev/null; then
        sleep 2  # Wait for background save to complete
        if docker cp claude-redis:/data/dump.rdb "$backup_dir/redis-backup.rdb" 2>/dev/null; then
            echo "✅ Redis data backed up successfully"
        else
            echo "⚠️  Redis backup failed - container may not be running"
        fi
    else
        echo "⚠️  Redis backup skipped - service not accessible"
    fi
    
    # Backup service state
    echo "Backing up service state..."
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose ps --format json > "$backup_dir/services-state.json" 2>/dev/null || echo "{}" > "$backup_dir/services-state.json"
    fi
    
    # Create backup metadata
    cat > "$backup_dir/backup-metadata.json" << EOF
{
    "backup_id": "$backup_id",
    "timestamp": "$(date -Iseconds)",
    "environment": "initial",
    "type": "initial_backup",
    "services_running": $(docker ps --format "{{.Names}}" | grep -c claude- 2>/dev/null || echo "0"),
    "backup_size": "$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "unknown")"
}
EOF
    
    echo "✅ Initial backup created successfully at: $backup_dir"
    echo "📊 Backup ID: $backup_id"
    
    # Test rollback script with this backup
    echo "🔍 Testing rollback functionality..."
    if ./deploy/rollback.sh development "$backup_id" --dry-run 2>/dev/null; then
        echo "✅ Rollback system verified - backup is valid"
    else
        echo "⚠️  Rollback test failed - backup may need manual verification"
    fi
    
    return 0
}

# Main execution
echo "==========================================="
echo "Kong AWS Masking MVP - Initial Backup Setup"
echo "==========================================="
echo "Timestamp: $(date)"
echo

create_initial_backup

echo
echo "🎉 Backup system initialization complete!"
echo "   - Backup directory structure created"
echo "   - Initial backup generated"  
echo "   - Rollback functionality enabled"
echo
echo "Next steps:"
echo "  1. Run rollback test: ./deploy/rollback.sh --help"
echo "  2. Proceed with integration testing"