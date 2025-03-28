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
    local dir="${SERVICE_DIRS[$service]}"
    
    # Get process ID if exists
    local pid=$(ps -ef | grep -v grep | grep "$pattern" | awk '{print $2}')
    
    if [ -n "$pid" ]; then
        # Check process working directory
        local pwd=$(readlink -f /proc/$pid/cwd)
        if [ "$pwd" = "$BASE_DIR/$dir" ]; then
            return 0  # Service is running from correct directory
        else
            log_message "Warning: $service process (PID: $pid) found but running from wrong directory: $pwd (expected: $BASE_DIR/$dir)"
            return 1  # Service is running but from wrong location
        fi
    else
        return 1  # Service is not running at all
    fi
}

# Function to get service status
get_service_status() {
    local service=$1
    local pattern="${SERVICE_PATTERNS[$service]}"
    local dir="${SERVICE_DIRS[$service]}"
    
    # Get process ID if exists
    local pid=$(ps -ef | grep -v grep | grep "$pattern" | awk '{print $2}')
    
    if [ -n "$pid" ]; then
        # Check process working directory
        local pwd=$(readlink -f /proc/$pid/cwd)
        if [ "$pwd" = "$BASE_DIR/$dir" ]; then
            echo "RUNNING"
        else
            echo "WRONG_LOCATION"
        fi
    elif [ -d "$BASE_DIR/$dir" ]; then
        echo "STOPPED"
    else
        echo "NO_DIRECTORY"
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
    local dir="${SERVICE_DIRS[$service]}"
    
    log_message "Starting $service service from $BASE_DIR/$dir..."
    cd "$BASE_DIR/$dir" && ./$command
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
        log_message "Service $service is not running from correct location"
        if check_service_dir "$service"; then
            # Kill any existing process running from wrong location
            ps -ef | grep -v grep | grep "${SERVICE_PATTERNS[$service]}" | grep -v "$BASE_DIR/${SERVICE_DIRS[$service]}" | awk '{print $2}' | xargs -r kill -9
            start_service "$service"
        else
            log_message "Service directory for $service does not exist at $BASE_DIR/${SERVICE_DIRS[$service]}"
        fi
    fi
}

# Function to check all services
check_all_services() {
    local all_running=true
    local running_services=()
    local stopped_services=()
    local wrong_location_services=()
    local no_directory_services=()
    
    log_message "=== Starting service status check ==="
    
    for service in "${!SERVICES[@]}"; do
        local status=$(get_service_status "$service")
        case $status in
            "RUNNING")
                running_services+=("$service")
                ;;
            "WRONG_LOCATION")
                wrong_location_services+=("$service")
                all_running=false
                ;;
            "STOPPED")
                stopped_services+=("$service")
                all_running=false
                ;;
            "NO_DIRECTORY")
                no_directory_services+=("$service")
                all_running=false
                ;;
        esac
    done
    
    # Log detailed status
    log_message "Service Status Summary:"
    if [ ${#running_services[@]} -gt 0 ]; then
        log_message "✓ Running services: ${running_services[*]}"
    fi
    if [ ${#stopped_services[@]} -gt 0 ]; then
        log_message "✗ Stopped services: ${stopped_services[*]}"
    fi
    if [ ${#wrong_location_services[@]} -gt 0 ]; then
        log_message "⚠ Services running from wrong location: ${wrong_location_services[*]}"
    fi
    if [ ${#no_directory_services[@]} -gt 0 ]; then
        log_message "❌ Missing service directories: ${no_directory_services[*]}"
    fi
    
    if [ "$all_running" = true ]; then
        log_message "✅ All services are running correctly"
    else
        log_message "⚠ Some services require attention"
    fi
    
    # Restart services that need it
    for service in "${stopped_services[@]}" "${wrong_location_services[@]}"; do
        check_and_restart_service "$service"
    done
    
    log_message "=== Service status check completed ==="
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