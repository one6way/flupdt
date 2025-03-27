#!/bin/bash

# Configuration
LOG_FILE="/var/log/system_monitor.log"
SCRIPT_LOG_FILE="script_operation.log"
EMAIL_TO="your-email@example.com"  # Change this to your email
CHECK_INTERVAL=300  # 5 minutes in seconds
EMAIL_INTERVAL=1800  # 30 minutes in seconds
LOG_RETENTION_HOURS=2  # Keep logs for 2 hours
ENABLE_LOG_CLEANUP=true  # Set to false to disable log cleanup
MONITOR_DIRS=("/opt/fl/flexloader/run/apl_service" "/opt/fl/flexloader/run/target.init-service" "/opt/fl/flexloader/run/mata.init-service")

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to get current date for log rotation
get_current_date() {
    date '+%Y%m%d'
}

# Function to clean old logs
clean_old_logs() {
    # Skip if log cleanup is disabled
    if [ "$ENABLE_LOG_CLEANUP" = false ]; then
        log_script_operation "Log cleanup is disabled, skipping..."
        return
    fi

    local current_time=$(date +%s)
    local retention_seconds=$((LOG_RETENTION_HOURS * 3600))
    
    # Clean system monitor log
    if [ -f "$LOG_FILE" ]; then
        local log_time=$(stat -c %Y "$LOG_FILE")
        if [ $((current_time - log_time)) -gt $retention_seconds ]; then
            log_script_operation "Cleaning old system monitor log"
            > "$LOG_FILE"
        fi
    fi
    
    # Clean script operation log
    if [ -f "$SCRIPT_LOG_FILE" ]; then
        local log_time=$(stat -c %Y "$SCRIPT_LOG_FILE")
        if [ $((current_time - log_time)) -gt $retention_seconds ]; then
            log_script_operation "Cleaning old script operation log"
            > "$SCRIPT_LOG_FILE"
        fi
    fi
}

# Function to log script operation
log_script_operation() {
    local message=$1
    local timestamp=$(get_timestamp)
    echo "[$timestamp] $message" | tee -a "$SCRIPT_LOG_FILE"
}

# Function to check RAM usage and top processes
check_ram_usage() {
    log_script_operation "Checking RAM usage and process statistics..."
    echo "=== Detailed RAM Usage Report at $(get_timestamp) ===" >> "$LOG_FILE"
    
    # Overall system memory status
    echo -e "\n=== System Memory Overview ===" >> "$LOG_FILE"
    free -h >> "$LOG_FILE"
    
    # Detailed memory information
    echo -e "\n=== Detailed Memory Information ===" >> "$LOG_FILE"
    cat /proc/meminfo >> "$LOG_FILE"
    
    # Swap usage
    echo -e "\n=== Swap Usage ===" >> "$LOG_FILE"
    swapon --show >> "$LOG_FILE"
    
    # Process memory statistics
    echo -e "\n=== Process Memory Statistics ===" >> "$LOG_FILE"
    echo "Format: PID | PPID | User | %CPU | %MEM | RSS | VSZ | Command" >> "$LOG_FILE"
    ps aux --sort=-%mem | awk '{printf "%-8s %-8s %-10s %-6s %-6s %-10s %-10s %s\n", $2, $3, $1, $3, $4, $6, $5, $11}' >> "$LOG_FILE"
    
    # Process tree with memory usage
    echo -e "\n=== Process Tree with Memory Usage ===" >> "$LOG_FILE"
    ps -eo pid,ppid,%mem,rss,cmd --forest >> "$LOG_FILE"
    
    # Memory usage by user
    echo -e "\n=== Memory Usage by User ===" >> "$LOG_FILE"
    ps aux | awk '{sum[$1] += $4} END {for (user in sum) print user, sum[user]"%"}' | sort -k2 -nr >> "$LOG_FILE"
    
    # Memory pressure
    echo -e "\n=== Memory Pressure ===" >> "$LOG_FILE"
    cat /proc/pressure/memory >> "$LOG_FILE"
    
    # Slab memory usage
    echo -e "\n=== Slab Memory Usage ===" >> "$LOG_FILE"
    cat /proc/slabinfo | grep -v "^#" | sort -rn -k 3 | head -n 20 >> "$LOG_FILE"
    
    # Huge pages
    echo -e "\n=== Huge Pages Status ===" >> "$LOG_FILE"
    cat /proc/meminfo | grep -i huge >> "$LOG_FILE"
    
    # Memory zones
    echo -e "\n=== Memory Zones ===" >> "$LOG_FILE"
    cat /proc/zoneinfo | grep -E "Node|zone" >> "$LOG_FILE"
    
    echo "=====================================" >> "$LOG_FILE"
    log_script_operation "RAM usage and process statistics check completed"
}

# Function to check system logs for OOM and process termination
check_system_logs() {
    local process_name=$1
    local last_check=$2
    
    log_script_operation "Checking system logs for process: $process_name"
    echo "[$(get_timestamp)] Checking system logs for $process_name since $last_check" >> "$LOG_FILE"
    
    # Check dmesg for OOM kills and kernel messages
    echo "=== Kernel Messages (dmesg) ===" >> "$LOG_FILE"
    dmesg | grep -i "out of memory" | grep "$process_name" | grep -A 5 "since $last_check" >> "$LOG_FILE"
    dmesg | grep -i "killed process" | grep "$process_name" | grep -A 3 "since $last_check" >> "$LOG_FILE"
    
    # Check system journal for process termination and system events
    echo -e "\n=== System Journal Events ===" >> "$LOG_FILE"
    journalctl --since "$last_check" | grep "$process_name" | grep -i "killed\|terminated\|oom\|failed\|error" >> "$LOG_FILE"
    
    # Check system logs for memory pressure and system state
    echo -e "\n=== System Memory State ===" >> "$LOG_FILE"
    journalctl --since "$last_check" | grep -i "memory pressure\|low memory\|swap\|out of memory" >> "$LOG_FILE"
    
    # Check process-specific logs if they exist
    echo -e "\n=== Process-specific Logs ===" >> "$LOG_FILE"
    if [ -d "/var/log/$process_name" ]; then
        find "/var/log/$process_name" -type f -mmin -5 -exec tail -n 50 {} \; >> "$LOG_FILE"
    fi
    
    # Check system resource limits
    echo -e "\n=== System Resource Limits ===" >> "$LOG_FILE"
    ulimit -a >> "$LOG_FILE"
    
    # Check current memory pressure
    echo -e "\n=== Current Memory Pressure ===" >> "$LOG_FILE"
    cat /proc/pressure/memory >> "$LOG_FILE"
    
    # Check if process was killed by OOM
    if dmesg | grep -i "out of memory" | grep "$process_name" | grep -q "since $last_check"; then
        echo -e "\n[$(get_timestamp)] WARNING: Process $process_name was killed by OOM killer!" >> "$LOG_FILE"
        echo "Memory pressure at time of kill:" >> "$LOG_FILE"
        free -h >> "$LOG_FILE"
        
        # Get detailed memory info at time of kill
        echo -e "\nDetailed memory information:" >> "$LOG_FILE"
        cat /proc/meminfo >> "$LOG_FILE"
        
        # Get system load at time of kill
        echo -e "\nSystem load at time of kill:" >> "$LOG_FILE"
        uptime >> "$LOG_FILE"
        
        log_script_operation "WARNING: Process $process_name was killed by OOM killer!"
    fi
    
    log_script_operation "System logs check completed for $process_name"
}

# Function to check directory existence and processes
check_directories() {
    log_script_operation "Starting directory check..."
    for dir in "${MONITOR_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            log_script_operation "WARNING: Directory $dir is missing!"
            echo "[$(get_timestamp)] WARNING: Directory $dir is missing!" >> "$LOG_FILE"
            
            # Get directory name for process search
            dir_name=$(basename "$dir")
            
            # Check if process is still running
            process_info=$(ps aux | grep "$dir_name" | grep -v grep)
            if [ -n "$process_info" ]; then
                log_script_operation "Found running process for $dir_name"
                echo "[$(get_timestamp)] Found running process for $dir_name:" >> "$LOG_FILE"
                echo "$process_info" >> "$LOG_FILE"
                
                # Get process memory usage
                echo "[$(get_timestamp)] Current memory usage for $dir_name:" >> "$LOG_FILE"
                ps -o pid,ppid,%mem,rss,cmd -p $(pgrep -f "$dir_name") >> "$LOG_FILE"
            else
                log_script_operation "No running process found for $dir_name"
                echo "[$(get_timestamp)] No running process found for $dir_name" >> "$LOG_FILE"
                
                # Check system logs for termination reason
                last_check=$(date -d "5 minutes ago" "+%Y-%m-%d %H:%M:%S")
                check_system_logs "$dir_name" "$last_check"
            fi
        else
            log_script_operation "Directory $dir exists and is accessible"
        fi
    done
    log_script_operation "Directory check completed"
}

# Function to send email report
send_email_report() {
    log_script_operation "Preparing to send email report..."
    if [ -f "$LOG_FILE" ]; then
        mail -s "System Monitoring Report - $(get_timestamp)" "$EMAIL_TO" < "$LOG_FILE"
        log_script_operation "Email report sent successfully"
    else
        log_script_operation "ERROR: Log file not found, email report not sent"
    fi
}

# Function to cleanup on exit
cleanup() {
    log_script_operation "Script terminated. Performing cleanup..."
    exit 0
}

# Set up trap for cleanup on script termination
trap cleanup SIGINT SIGTERM

# Print startup information
echo "==============================================="
echo "System Monitoring Script Started"
echo "Time: $(get_timestamp)"
echo "Log file: $LOG_FILE"
echo "Script operation log: $SCRIPT_LOG_FILE"
echo "Check interval: $CHECK_INTERVAL seconds"
echo "Email interval: $EMAIL_INTERVAL seconds"
echo "Log retention period: $LOG_RETENTION_HOURS hours"
echo "Log cleanup: $([ "$ENABLE_LOG_CLEANUP" = true ] && echo "Enabled" || echo "Disabled")"
echo "Monitored directories:"
for dir in "${MONITOR_DIRS[@]}"; do
    echo "  - $dir"
done
echo "==============================================="

# Main monitoring loop
last_email_time=0

while true; do
    current_time=$(date +%s)
    
    # Clean old logs
    clean_old_logs
    
    # Check RAM usage every 5 minutes
    check_ram_usage
    
    # Check directories
    check_directories
    
    # Send email report every 30 minutes
    if [ $((current_time - last_email_time)) -ge $EMAIL_INTERVAL ]; then
        send_email_report
        last_email_time=$current_time
    fi
    
    log_script_operation "Waiting for next check interval..."
    sleep $CHECK_INTERVAL
done 