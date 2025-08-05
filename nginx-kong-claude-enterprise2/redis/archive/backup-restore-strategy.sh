#!/bin/bash

# Redis Backup and Restore Strategy Implementation
# For AWS Masker Redis Infrastructure

set -euo pipefail

# Configuration
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL}"
BACKUP_DIR="${BACKUP_DIR:-/data/redis-backups}"
S3_BUCKET="${S3_BUCKET:-your-aws-masker-backups}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
LOG_FILE="${LOG_FILE:-/var/log/redis-backup.log}"

# Create backup directory if not exists
mkdir -p "$BACKUP_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check Redis connection
check_redis_connection() {
    log "Checking Redis connection..."
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping > /dev/null 2>&1 || \
        error_exit "Cannot connect to Redis at $REDIS_HOST:$REDIS_PORT"
    log "Redis connection successful"
}

# Perform RDB backup
perform_rdb_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/redis-backup-${timestamp}.rdb"
    
    log "Starting RDB backup to $backup_file"
    
    # Trigger BGSAVE
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" BGSAVE
    
    # Wait for backup to complete
    while [ $(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" LASTSAVE) -eq $(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" LASTSAVE) ]; do
        sleep 1
    done
    
    # Copy the RDB file
    docker cp kong-redis:/data/aws-masker.rdb "$backup_file" 2>/dev/null || \
        cp /data/aws-masker.rdb "$backup_file"
    
    log "RDB backup completed: $backup_file"
    echo "$backup_file"
}

# Perform AOF backup
perform_aof_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/redis-backup-${timestamp}.aof"
    
    log "Starting AOF backup to $backup_file"
    
    # Copy the AOF file
    docker cp kong-redis:/data/aws-masker.aof "$backup_file" 2>/dev/null || \
        cp /data/aws-masker.aof "$backup_file"
    
    log "AOF backup completed: $backup_file"
    echo "$backup_file"
}

# Backup specific database
backup_database() {
    local db_num=$1
    local db_name=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/redis-db${db_num}-${db_name}-${timestamp}.rdb"
    
    log "Backing up database $db_num ($db_name)"
    
    # Export specific database using redis-cli
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" -n "$db_num" \
        --rdb "$backup_file" 2>/dev/null || {
        # Fallback method if --rdb not supported
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" <<EOF
SELECT $db_num
BGSAVE
EOF
        sleep 5
        cp /data/aws-masker.rdb "$backup_file"
    }
    
    log "Database $db_num backup completed: $backup_file"
    echo "$backup_file"
}

# Compress backup
compress_backup() {
    local backup_file=$1
    local compressed_file="${backup_file}.gz"
    
    log "Compressing backup: $backup_file"
    gzip -c "$backup_file" > "$compressed_file"
    
    # Verify compression
    if [ -f "$compressed_file" ] && [ -s "$compressed_file" ]; then
        rm "$backup_file"
        log "Compression completed: $compressed_file"
        echo "$compressed_file"
    else
        error_exit "Compression failed for $backup_file"
    fi
}

# Upload to S3
upload_to_s3() {
    local file=$1
    local s3_key="redis-backups/$(basename "$file")"
    
    log "Uploading to S3: s3://$S3_BUCKET/$s3_key"
    
    aws s3 cp "$file" "s3://$S3_BUCKET/$s3_key" \
        --region "$AWS_REGION" \
        --storage-class STANDARD_IA \
        --metadata "backup-type=redis,timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)" || \
        error_exit "S3 upload failed"
    
    log "S3 upload completed"
}

# Restore from RDB backup
restore_rdb_backup() {
    local backup_file=$1
    
    log "Starting RDB restore from $backup_file"
    
    # Stop Redis temporarily
    docker stop kong-redis 2>/dev/null || \
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" SHUTDOWN NOSAVE
    
    # Replace RDB file
    cp "$backup_file" /data/aws-masker.rdb
    
    # Restart Redis
    docker start kong-redis 2>/dev/null || \
        redis-server /etc/redis/redis.conf --daemonize yes
    
    # Wait for Redis to start
    sleep 5
    check_redis_connection
    
    log "RDB restore completed"
}

# Restore from AOF backup
restore_aof_backup() {
    local backup_file=$1
    
    log "Starting AOF restore from $backup_file"
    
    # Stop Redis
    docker stop kong-redis 2>/dev/null || \
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" SHUTDOWN NOSAVE
    
    # Replace AOF file
    cp "$backup_file" /data/aws-masker.aof
    
    # Restart Redis with AOF
    docker start kong-redis 2>/dev/null || \
        redis-server /etc/redis/redis.conf --daemonize yes
    
    # Wait for Redis to start and load AOF
    sleep 10
    check_redis_connection
    
    log "AOF restore completed"
}

# Verify backup integrity
verify_backup() {
    local backup_file=$1
    
    log "Verifying backup integrity: $backup_file"
    
    # Check if file exists and not empty
    if [ ! -f "$backup_file" ] || [ ! -s "$backup_file" ]; then
        error_exit "Backup file is missing or empty: $backup_file"
    fi
    
    # For RDB files, use redis-check-rdb
    if [[ "$backup_file" == *.rdb ]]; then
        redis-check-rdb "$backup_file" || error_exit "RDB backup verification failed"
    fi
    
    # For AOF files, use redis-check-aof
    if [[ "$backup_file" == *.aof ]]; then
        redis-check-aof "$backup_file" || error_exit "AOF backup verification failed"
    fi
    
    log "Backup verification passed"
}

# Clean old backups
cleanup_old_backups() {
    local retention_days=${1:-7}
    
    log "Cleaning backups older than $retention_days days"
    
    # Local cleanup
    find "$BACKUP_DIR" -name "redis-backup-*" -type f -mtime +$retention_days -delete
    
    # S3 cleanup
    aws s3 ls "s3://$S3_BUCKET/redis-backups/" --region "$AWS_REGION" | \
    while read -r line; do
        backup_date=$(echo "$line" | awk '{print $1}')
        backup_file=$(echo "$line" | awk '{print $4}')
        
        if [ -n "$backup_date" ] && [ -n "$backup_file" ]; then
            backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$backup_date" +%s)
            current_timestamp=$(date +%s)
            age_days=$(( (current_timestamp - backup_timestamp) / 86400 ))
            
            if [ $age_days -gt $retention_days ]; then
                log "Deleting old S3 backup: $backup_file"
                aws s3 rm "s3://$S3_BUCKET/redis-backups/$backup_file" --region "$AWS_REGION"
            fi
        fi
    done
    
    log "Cleanup completed"
}

# Full backup procedure
full_backup() {
    log "Starting full backup procedure"
    
    check_redis_connection
    
    # Perform RDB backup
    rdb_backup=$(perform_rdb_backup)
    verify_backup "$rdb_backup"
    compressed_rdb=$(compress_backup "$rdb_backup")
    upload_to_s3 "$compressed_rdb"
    
    # Backup individual databases with descriptions
    backup_database 0 "active-mappings"
    backup_database 1 "historical-data" 
    backup_database 2 "unmask-mappings"
    backup_database 3 "metrics"
    
    # Perform AOF backup (optional, larger file)
    if [ "${BACKUP_AOF:-false}" == "true" ]; then
        aof_backup=$(perform_aof_backup)
        verify_backup "$aof_backup"
        compressed_aof=$(compress_backup "$aof_backup")
        upload_to_s3 "$compressed_aof"
    fi
    
    # Cleanup old backups
    cleanup_old_backups 7
    
    log "Full backup procedure completed"
}

# Incremental backup using AOF
incremental_backup() {
    log "Starting incremental backup"
    
    check_redis_connection
    
    # Copy current AOF file
    timestamp=$(date +%Y%m%d_%H%M%S)
    aof_backup="$BACKUP_DIR/redis-incremental-${timestamp}.aof"
    
    docker cp kong-redis:/data/aws-masker.aof "$aof_backup" 2>/dev/null || \
        cp /data/aws-masker.aof "$aof_backup"
    
    verify_backup "$aof_backup"
    compressed_aof=$(compress_backup "$aof_backup")
    upload_to_s3 "$compressed_aof"
    
    log "Incremental backup completed"
}

# Disaster recovery procedure
disaster_recovery() {
    local recovery_point=$1
    
    log "Starting disaster recovery to point: $recovery_point"
    
    # Download backup from S3 if needed
    if [[ "$recovery_point" == s3://* ]]; then
        local local_file="$BACKUP_DIR/$(basename "$recovery_point")"
        aws s3 cp "$recovery_point" "$local_file" --region "$AWS_REGION"
        recovery_point="$local_file"
    fi
    
    # Decompress if needed
    if [[ "$recovery_point" == *.gz ]]; then
        gunzip -c "$recovery_point" > "${recovery_point%.gz}"
        recovery_point="${recovery_point%.gz}"
    fi
    
    # Verify backup before restore
    verify_backup "$recovery_point"
    
    # Determine backup type and restore
    if [[ "$recovery_point" == *.rdb ]]; then
        restore_rdb_backup "$recovery_point"
    elif [[ "$recovery_point" == *.aof ]]; then
        restore_aof_backup "$recovery_point"
    else
        error_exit "Unknown backup type: $recovery_point"
    fi
    
    # Verify data after restore
    log "Verifying restored data..."
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" <<EOF
SELECT 2
DBSIZE
SELECT 0
DBSIZE
EOF
    
    log "Disaster recovery completed"
}

# Monitor backup health
monitor_backup_health() {
    log "Checking backup health..."
    
    # Check last backup time
    last_backup=$(ls -t "$BACKUP_DIR"/redis-backup-*.gz 2>/dev/null | head -1)
    if [ -z "$last_backup" ]; then
        error_exit "No backups found!"
    fi
    
    last_backup_time=$(stat -c %Y "$last_backup" 2>/dev/null || stat -f %m "$last_backup")
    current_time=$(date +%s)
    age_hours=$(( (current_time - last_backup_time) / 3600 ))
    
    if [ $age_hours -gt 24 ]; then
        log "WARNING: Last backup is $age_hours hours old"
    else
        log "Last backup is $age_hours hours old (OK)"
    fi
    
    # Check S3 connectivity
    aws s3 ls "s3://$S3_BUCKET/redis-backups/" --region "$AWS_REGION" > /dev/null 2>&1 || \
        log "WARNING: Cannot access S3 bucket"
    
    # Check disk space
    available_space=$(df -BG "$BACKUP_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 10 ]; then
        log "WARNING: Low disk space: ${available_space}GB available"
    fi
    
    log "Backup health check completed"
}

# Main function
main() {
    case "${1:-}" in
        backup)
            full_backup
            ;;
        incremental)
            incremental_backup
            ;;
        restore)
            if [ -z "${2:-}" ]; then
                error_exit "Usage: $0 restore <backup-file>"
            fi
            disaster_recovery "$2"
            ;;
        verify)
            if [ -z "${2:-}" ]; then
                error_exit "Usage: $0 verify <backup-file>"
            fi
            verify_backup "$2"
            ;;
        cleanup)
            cleanup_old_backups "${2:-7}"
            ;;
        monitor)
            monitor_backup_health
            ;;
        schedule)
            # Setup cron jobs
            cat > /etc/cron.d/redis-backup <<EOF
# Redis backup schedule
0 */4 * * * root $0 backup >> $LOG_FILE 2>&1
0 * * * * root $0 incremental >> $LOG_FILE 2>&1
0 6 * * * root $0 monitor >> $LOG_FILE 2>&1
0 2 * * 0 root $0 cleanup 7 >> $LOG_FILE 2>&1
EOF
            log "Backup schedule configured"
            ;;
        *)
            cat <<EOF
Redis Backup and Restore Strategy

Usage: $0 {command} [options]

Commands:
  backup      - Perform full backup (RDB + individual DBs)
  incremental - Perform incremental backup (AOF)
  restore     - Restore from backup file
  verify      - Verify backup integrity
  cleanup     - Clean old backups
  monitor     - Check backup health
  schedule    - Setup automated backup cron jobs

Examples:
  $0 backup
  $0 restore /data/redis-backups/redis-backup-20250128_103000.rdb
  $0 restore s3://bucket/redis-backups/redis-backup-20250128_103000.rdb.gz
  $0 cleanup 30
  $0 monitor

Environment Variables:
  REDIS_HOST     - Redis host (default: localhost)
  REDIS_PORT     - Redis port (default: 6379)
  REDIS_PASSWORD - Redis password
  BACKUP_DIR     - Local backup directory
  S3_BUCKET      - S3 bucket for remote backups
  AWS_REGION     - AWS region
  BACKUP_AOF     - Include AOF in full backup (true/false)

EOF
            ;;
    esac
}

# Run main function
main "$@"