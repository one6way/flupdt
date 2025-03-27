#!/bin/bash

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/system_monitor.log"
SCRIPT_LOG_FILE="$SCRIPT_DIR/script_operation.log"
EMAIL_TO="your-email@example.com"  # Change this to your email
CHECK_INTERVAL=300  # 5 minutes in seconds
EMAIL_INTERVAL=1800  # 30 minutes in seconds
MONITOR_DIRS=("/opt/fl/flexloader/run/apl_service" "/opt/fl/flexloader/run/target.init-service" "/opt/fl/flexloader/run/mata.init-service")

# Trap for script termination
trap 'cleanup_and_exit' SIGINT SIGTERM

# Function to cleanup and exit
cleanup_and_exit() {
    log_script_operation "Script received termination signal. Cleaning up..."
    log_script_operation "Script terminated at $(get_timestamp)"
    exit 0
}

# Function to check required utilities
check_requirements() {
    local required_utils=("free" "ps" "dmesg" "journalctl" "mail" "tee" "grep" "find")
    local missing_utils=()
    
    for util in "${required_utils[@]}"; do
        if ! command -v "$util" &> /dev/null; then
            missing_utils+=("$util")
        fi
    done
    
    if [ ${#missing_utils[@]} -ne 0 ]; then
        echo "ERROR: Missing required utilities: ${missing_utils[*]}"
        echo "Please install missing utilities before running the script."
        exit 1
    fi
}

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to log script operation
log_script_operation() {
    local message=$1
    local timestamp=$(get_timestamp)
    echo "[$timestamp] $message" | tee -a "$SCRIPT_LOG_FILE"
}

# Function to check RAM usage and top processes
check_ram_usage() {
    log_script_operation "Checking RAM usage and top processes..."
    {
        echo "=== RAM Usage Report at $(get_timestamp) ==="
        free -h || echo "ERROR: Failed to get RAM usage"
        echo -e "\nTop 5 memory-consuming processes:"
        ps aux --sort=-%mem | head -n 6 || echo "ERROR: Failed to get process list"
        echo "====================================="
    } >> "$LOG_FILE"
    log_script_operation "RAM usage check completed"
}

# Function to check system logs for OOM and process termination
check_system_logs() {
    local process_name=$1
    local last_check=$2
    
    log_script_operation "Checking system logs for process: $process_name"
    {
        echo "[$(get_timestamp)] Checking system logs for $process_name since $last_check"
        
        # Check dmesg for OOM kills and kernel messages
        echo "=== Kernel Messages (dmesg) ==="
        dmesg | grep -i "out of memory" | grep "$process_name" | grep -A 5 "since $last_check" || true
        dmesg | grep -i "killed process" | grep "$process_name" | grep -A 3 "since $last_check" || true
        
        # Check system journal for process termination and system events
        echo -e "\n=== System Journal Events ==="
        journalctl --since "$last_check" | grep "$process_name" | grep -i "killed\|terminated\|oom\|failed\|error" || true
        
        # Check system logs for memory pressure and system state
        echo -e "\n=== System Memory State ==="
        journalctl --since "$last_check" | grep -i "memory pressure\|low memory\|swap\|out of memory" || true
        
        # Check process-specific logs if they exist
        echo -e "\n=== Process-specific Logs ==="
        if [ -d "/var/log/$process_name" ]; then
            find "/var/log/$process_name" -type f -mmin -5 -exec tail -n 50 {} \; || true
        fi
        
        # Check system resource limits
        echo -e "\n=== System Resource Limits ==="
        ulimit -a || echo "ERROR: Failed to get resource limits"
        
        # Check current memory pressure
        echo -e "\n=== Current Memory Pressure ==="
        if [ -f "/proc/pressure/memory" ]; then
            cat /proc/pressure/memory || echo "ERROR: Failed to read memory pressure"
        else
            echo "Memory pressure file not available"
        fi
    } >> "$LOG_FILE"
    
    # Check if process was killed by OOM
    if dmesg | grep -i "out of memory" | grep "$process_name" | grep -q "since $last_check"; then
        {
            echo -e "\n[$(get_timestamp)] WARNING: Process $process_name was killed by OOM killer!"
            echo "Memory pressure at time of kill:"
            free -h || echo "ERROR: Failed to get memory usage"
            
            echo -e "\nDetailed memory information:"
            cat /proc/meminfo || echo "ERROR: Failed to get detailed memory info"
            
            echo -e "\nSystem load at time of kill:"
            uptime || echo "ERROR: Failed to get system load"
        } >> "$LOG_FILE"
        
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
            {
                echo "[$(get_timestamp)] WARNING: Directory $dir is missing!"
                
                # Get directory name for process search
                dir_name=$(basename "$dir")
                
                # Check if process is still running
                process_info=$(ps aux | grep "$dir_name" | grep -v grep)
                if [ -n "$process_info" ]; then
                    log_script_operation "Found running process for $dir_name"
                    echo "Found running process for $dir_name:"
                    echo "$process_info"
                    
                    # Get process memory usage
                    echo "Current memory usage for $dir_name:"
                    ps -o pid,ppid,%mem,rss,cmd -p $(pgrep -f "$dir_name") || echo "ERROR: Failed to get process memory usage"
                else
                    log_script_operation "No running process found for $dir_name"
                    echo "No running process found for $dir_name"
                    
                    # Check system logs for termination reason
                    last_check=$(date -d "5 minutes ago" "+%Y-%m-%d %H:%M:%S")
                    check_system_logs "$dir_name" "$last_check"
                fi
            } >> "$LOG_FILE"
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
        if mail -s "System Monitoring Report - $(get_timestamp)" "$EMAIL_TO" < "$LOG_FILE"; then
            log_script_operation "Email report sent successfully"
        else
            log_script_operation "ERROR: Failed to send email report"
        fi
    else
        log_script_operation "ERROR: Log file not found, email report not sent"
    fi
}

# Main script execution
main() {
    # Check requirements
    check_requirements
    
    # Create log files if they don't exist
    touch "$LOG_FILE" "$SCRIPT_LOG_FILE" || {
        echo "ERROR: Failed to create log files"
        exit 1
    }
    
    # Print startup information
    echo "==============================================="
    echo "System Monitoring Script Started"
    echo "Time: $(get_timestamp)"
    echo "Script directory: $SCRIPT_DIR"
    echo "Log file: $LOG_FILE"
    echo "Script operation log: $SCRIPT_LOG_FILE"
    echo "Check interval: $CHECK_INTERVAL seconds"
    echo "Email interval: $EMAIL_INTERVAL seconds"
    echo "Monitored directories:"
    for dir in "${MONITOR_DIRS[@]}"; do
        echo "  - $dir"
    done
    echo "==============================================="
    
    # Main monitoring loop
    last_email_time=0
    
    while true; do
        current_time=$(date +%s)
        
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
}

# Run main function
main 