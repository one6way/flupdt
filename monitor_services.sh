#!/bin/bash

# Configuration
BASE_DIR="/opt/flbde/flex"
LOG_DIR="/var/log/service_monitor"  # Directory for log files
LOG_FILE="$LOG_DIR/service_monitor.log"
CHECK_INTERVAL=300  # 5 minutes
MAX_LOG_AGE=7  # Keep logs for 7 days

# Service configurations
declare -A SERVICES=(
    ["meta"]="meta-init-service"
    ["target"]="target-init-service"
    ["extract"]="extract-all -daemon"
    ["apply"]="apply-all -daemon"
)

declare -A SERVICE_PATTERNS=(
    ["meta"]="ru.byt.cli target init-service"
    ["target"]="ru.byt.cli target init-service"
    ["extract"]="ru.byt.cli target init-service"
    ["apply"]="ru.byt.cli target init-service"
)

declare -A SERVICE_DIRS=(
    ["meta"]="meta.init-service"
    ["target"]="target.init-service"
    ["extract"]="ext_service"
    ["apply"]="apl_service"
)

# Function to create log directory if it doesn't exist
create_log_dir() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi
}

# Function to rotate log files
rotate_logs() {
    local current_date=$(date '+%Y-%m-%d')
    local old_log="$LOG_FILE.$current_date"
    
    if [ -f "$LOG_FILE" ]; then
        mv "$LOG_FILE" "$old_log"
        gzip "$old_log"
    fi
    
    # Clean up old logs
    find "$LOG_DIR" -name "service_monitor.log.*.gz" -mtime +$MAX_LOG_AGE -delete
}

# Function to log messages
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
    echo "[$timestamp] $1"
}

# Function to check if service is running
check_service() {
    local service=$1
    local pattern="${SERVICE_PATTERNS[$service]}"
    
    if ps -ef | grep -v grep | grep -q "$pattern"; then
        return 0  # Service is running
    else
        return 1  # Service is not running
    fi
}

# Function to check if service directory exists
check_service_dir() {
    local service=$1
    local dir="${SERVICE_DIRS[$service]}"
    
    if [ -d "$BASE_DIR/$dir" ]; then
        return 0  # Directory exists
    else
        return 1  # Directory does not exist
    fi
}

# Function to start service
start_service() {
    local service=$1
    local command="${SERVICES[$service]}"
    
    log_message "Starting $service service..."
    cd "$BASE_DIR" && ./$command
    if [ $? -eq 0 ]; then
        log_message "Successfully started $service service"
    else
        log_message "Failed to start $service service"
    fi
}

# Function to check and restart service
check_and_restart_service() {
    local service=$1
    
    if ! check_service "$service"; then
        log_message "Service $service is not running"
        if check_service_dir "$service"; then
            start_service "$service"
        else
            log_message "Service directory for $service does not exist"
        fi
    fi
}

# Function to check all services
check_all_services() {
    for service in "${!SERVICES[@]}"; do
        check_and_restart_service "$service"
    done
}

# Function to check specific service
check_specific_service() {
    local service=$1
    if [ -n "${SERVICES[$service]}" ]; then
        check_and_restart_service "$service"
    else
        log_message "Unknown service: $service"
    fi
}

# Main script
create_log_dir
echo "Service Monitor Started"
log_message "Service Monitor Started"

# Check command line arguments
if [ $# -eq 0 ]; then
    # No arguments - monitor all services
    while true; do
        check_all_services
        sleep $CHECK_INTERVAL
        rotate_logs
    done
else
    # Monitor specific services
    while true; do
        for service in "$@"; do
            check_specific_service "$service"
        done
        sleep $CHECK_INTERVAL
        rotate_logs
    done
fi 