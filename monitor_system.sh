#!/bin/bash

# Configuration
LOG_FILE="/var/log/system_monitor.log"
EMAIL_TO="your-email@example.com"  # Change this to your email
CHECK_INTERVAL=300  # 5 minutes in seconds
EMAIL_INTERVAL=1800  # 30 minutes in seconds
MONITOR_DIRS=("/opt/fl/flexloader/run/apl_service" "/opt/fl/flexloader/run/target.init-service" "/opt/fl/flexloader/run/mata.init-service")

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to check RAM usage and top processes
check_ram_usage() {
    echo "=== RAM Usage Report at $(get_timestamp) ===" >> "$LOG_FILE"
    free -h >> "$LOG_FILE"
    echo -e "\nTop 5 memory-consuming processes:" >> "$LOG_FILE"
    ps aux --sort=-%mem | head -n 6 >> "$LOG_FILE"
    echo "=====================================" >> "$LOG_FILE"
}

# Function to check system logs for OOM and process termination
check_system_logs() {
    local process_name=$1
    local last_check=$2
    
    echo "[$(get_timestamp)] Checking system logs for $process_name since $last_check" >> "$LOG_FILE"
    
    # Check dmesg for OOM kills
    dmesg | grep -i "out of memory" | grep "$process_name" | grep -A 5 "since $last_check" >> "$LOG_FILE"
    
    # Check system journal for process termination
    journalctl --since "$last_check" | grep "$process_name" | grep -i "killed\|terminated\|oom" >> "$LOG_FILE"
    
    # Check system logs for memory pressure
    journalctl --since "$last_check" | grep -i "memory pressure\|low memory" >> "$LOG_FILE"
}

# Function to check directory existence and processes
check_directories() {
    for dir in "${MONITOR_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "[$(get_timestamp)] WARNING: Directory $dir is missing!" >> "$LOG_FILE"
            
            # Get directory name for process search
            dir_name=$(basename "$dir")
            
            # Check if process is still running
            process_info=$(ps aux | grep "$dir_name" | grep -v grep)
            if [ -n "$process_info" ]; then
                echo "[$(get_timestamp)] Found running process for $dir_name:" >> "$LOG_FILE"
                echo "$process_info" >> "$LOG_FILE"
                
                # Get process memory usage
                echo "[$(get_timestamp)] Current memory usage for $dir_name:" >> "$LOG_FILE"
                ps -o pid,ppid,%mem,rss,cmd -p $(pgrep -f "$dir_name") >> "$LOG_FILE"
            else
                echo "[$(get_timestamp)] No running process found for $dir_name" >> "$LOG_FILE"
                
                # Check system logs for termination reason
                last_check=$(date -d "5 minutes ago" "+%Y-%m-%d %H:%M:%S")
                check_system_logs "$dir_name" "$last_check"
                
                # Check if process was killed by OOM
                if dmesg | grep -i "out of memory" | grep "$dir_name" | grep -q "since $last_check"; then
                    echo "[$(get_timestamp)] WARNING: Process $dir_name was killed by OOM killer!" >> "$LOG_FILE"
                    echo "Memory pressure at time of kill:" >> "$LOG_FILE"
                    free -h >> "$LOG_FILE"
                fi
            fi
        fi
    done
}

# Function to send email report
send_email_report() {
    if [ -f "$LOG_FILE" ]; then
        mail -s "System Monitoring Report - $(get_timestamp)" "$EMAIL_TO" < "$LOG_FILE"
    fi
}

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
    
    sleep $CHECK_INTERVAL
done 