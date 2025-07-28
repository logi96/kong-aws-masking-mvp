#!/bin/sh
# Redis Backup Script for Production

set -e

# Configuration
REDIS_HOST=${REDIS_HOST:-redis}
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_PASSWORD=${REDIS_PASSWORD}
BACKUP_DIR="/backups"
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="redis_backup_${TIMESTAMP}"

# Create backup directory if not exists
mkdir -p "${BACKUP_DIR}"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Perform backup
perform_backup() {
    log "Starting Redis backup..."
    
    # Connect to Redis and create backup
    if [ -n "$REDIS_PASSWORD" ]; then
        export REDISCLI_AUTH="$REDIS_PASSWORD"
    fi
    
    # Save current state
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" BGSAVE
    
    # Wait for backup to complete
    log "Waiting for background save to complete..."
    while [ "$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE)" = "$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE)" ]; do
        sleep 1
    done
    
    # Copy dump file
    log "Copying dump file..."
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --rdb "${BACKUP_DIR}/${BACKUP_NAME}.rdb"
    
    # Compress backup
    log "Compressing backup..."
    gzip -9 "${BACKUP_DIR}/${BACKUP_NAME}.rdb"
    
    # Create metadata file
    cat > "${BACKUP_DIR}/${BACKUP_NAME}.meta" <<EOF
{
    "timestamp": "${TIMESTAMP}",
    "redis_version": "$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO server | grep redis_version | cut -d: -f2 | tr -d '\r')",
    "db_size": $(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" DBSIZE | cut -d' ' -f1),
    "used_memory": "$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')",
    "backup_size": "$(du -h ${BACKUP_DIR}/${BACKUP_NAME}.rdb.gz | cut -f1)"
}
EOF
    
    log "Backup completed: ${BACKUP_NAME}.rdb.gz"
}

# Clean old backups
cleanup_old_backups() {
    log "Cleaning up old backups..."
    
    # Find and delete backups older than retention period
    find "${BACKUP_DIR}" -name "redis_backup_*.rdb.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete
    find "${BACKUP_DIR}" -name "redis_backup_*.meta" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete
    
    # Keep minimum number of backups
    local backup_count=$(ls -1 "${BACKUP_DIR}"/redis_backup_*.rdb.gz 2>/dev/null | wc -l)
    if [ "$backup_count" -lt 3 ]; then
        log "Keeping minimum 3 backups"
        return
    fi
    
    log "Cleanup completed"
}

# Upload to S3 (optional)
upload_to_s3() {
    if [ -n "$BACKUP_S3_BUCKET" ] && command -v aws >/dev/null 2>&1; then
        log "Uploading backup to S3..."
        
        aws s3 cp "${BACKUP_DIR}/${BACKUP_NAME}.rdb.gz" \
            "s3://${BACKUP_S3_BUCKET}/redis-backups/${BACKUP_NAME}.rdb.gz" \
            --storage-class GLACIER_IR
        
        aws s3 cp "${BACKUP_DIR}/${BACKUP_NAME}.meta" \
            "s3://${BACKUP_S3_BUCKET}/redis-backups/${BACKUP_NAME}.meta"
        
        log "S3 upload completed"
    fi
}

# Verify backup
verify_backup() {
    log "Verifying backup..."
    
    # Check if backup file exists and has size > 0
    if [ ! -f "${BACKUP_DIR}/${BACKUP_NAME}.rdb.gz" ]; then
        log "ERROR: Backup file not found!"
        return 1
    fi
    
    local file_size=$(stat -c%s "${BACKUP_DIR}/${BACKUP_NAME}.rdb.gz" 2>/dev/null || stat -f%z "${BACKUP_DIR}/${BACKUP_NAME}.rdb.gz")
    if [ "$file_size" -eq 0 ]; then
        log "ERROR: Backup file is empty!"
        return 1
    fi
    
    # Test decompression
    if ! gzip -t "${BACKUP_DIR}/${BACKUP_NAME}.rdb.gz"; then
        log "ERROR: Backup file is corrupted!"
        return 1
    fi
    
    log "Backup verification passed"
    return 0
}

# Send notification
send_notification() {
    local status=$1
    local message=$2
    
    if [ -n "$ALERT_WEBHOOK_URL" ]; then
        wget -qO- --post-data="{
            \"text\": \"Redis Backup ${status}: ${message}\",
            \"backup_name\": \"${BACKUP_NAME}\",
            \"timestamp\": \"${TIMESTAMP}\"
        }" "$ALERT_WEBHOOK_URL" || true
    fi
}

# Main execution
main() {
    log "Redis backup job started"
    
    # Perform backup
    if perform_backup; then
        # Verify backup
        if verify_backup; then
            # Upload to S3 if configured
            upload_to_s3
            
            # Clean old backups
            cleanup_old_backups
            
            send_notification "SUCCESS" "Backup ${BACKUP_NAME} completed successfully"
            log "Backup job completed successfully"
            exit 0
        else
            send_notification "FAILED" "Backup ${BACKUP_NAME} verification failed"
            log "ERROR: Backup verification failed"
            exit 1
        fi
    else
        send_notification "FAILED" "Backup ${BACKUP_NAME} creation failed"
        log "ERROR: Backup creation failed"
        exit 1
    fi
}

# Run main function
main