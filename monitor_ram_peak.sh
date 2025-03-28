#!/bin/bash

# Configuration
LOG_DIR="/var/log/ram_monitor"
LOG_FILE="$LOG_DIR/ram_peak.log"
CHECK_INTERVAL=60  # Check every minute
REPORT_INTERVAL=1200  # Report every 20 minutes
MAX_LOG_AGE=7  # Keep logs for 7 days

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
    
    # Only rotate if the log file exists and is older than 5 minutes
    if [ -f "$LOG_FILE" ]; then
        local file_age=$(($(date +%s) - $(stat -c %Y "$LOG_FILE")))
        if [ $file_age -ge 300 ]; then  # 300 seconds = 5 minutes
            mv "$LOG_FILE" "$old_log"
            gzip "$old_log"
            log_message "Rotated log file after $file_age seconds"
        fi
    fi
    
    # Clean up old logs
    find "$LOG_DIR" -name "ram_peak.log.*.gz" -mtime +$MAX_LOG_AGE -delete
}

# Function to log messages
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
    echo "[$timestamp] $1"
}

# Function to get current RAM usage
get_ram_usage() {
    free -m | grep Mem | awk '{print $3}'
}

# Function to get current RAM usage percentage
get_ram_percentage() {
    free | grep Mem | awk '{print $3/$2 * 100.0}'
}

# Function to get current CPU usage percentage
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}'
}

# Function to get detailed process info
get_process_details() {
    local pid=$1
    local exe_path=$(readlink -f /proc/$pid/exe 2>/dev/null)
    local cmdline=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')
    local cwd=$(readlink -f /proc/$pid/cwd 2>/dev/null)
    local status=$(cat /proc/$pid/status 2>/dev/null | grep "Name:" | awk '{print $2}')
    
    echo "Process Details:"
    echo "  PID: $pid"
    echo "  Name: $status"
    echo "  Executable: $exe_path"
    echo "  Working Directory: $cwd"
    echo "  Command Line: $cmdline"
}

# Function to get top memory-consuming processes with details
get_top_processes() {
    local top_process=$(ps aux --sort=-%mem | head -n 2 | tail -n 1)
    local pid=$(echo "$top_process" | awk '{print $2}')
    
    echo "Top Memory Process:"
    echo "$top_process"
    get_process_details "$pid"
}

# Function to get top CPU-consuming processes with details
get_top_cpu_processes() {
    local top_process=$(ps aux --sort=-%cpu | head -n 2 | tail -n 1)
    local pid=$(echo "$top_process" | awk '{print $2}')
    
    echo "Top CPU Process:"
    echo "$top_process"
    get_process_details "$pid"
}

# Function to generate peak report
generate_peak_report() {
    local peak_time=$1
    local peak_ram_usage=$2
    local peak_ram_percentage=$3
    local peak_cpu_usage=$4
    
    log_message "=== System Peak Report for $(date '+%Y-%m-%d %H:%M:%S') ==="
    log_message "Peak RAM Usage: ${peak_ram_usage}MB (${peak_ram_percentage}%)"
    log_message "Peak CPU Usage: ${peak_cpu_usage}%"
    log_message "Peak Time: $peak_time"
    
    log_message "Top Memory-Consuming Process Details:"
    get_top_processes | while read line; do
        log_message "$line"
    done
    
    log_message "Top CPU-Consuming Process Details:"
    get_top_cpu_processes | while read line; do
        log_message "$line"
    done
    
    log_message "====================================="
}

# Main script
create_log_dir
echo "System Peak Monitor Started"
log_message "System Peak Monitor Started"

# Initialize variables
peak_ram_usage=0
peak_ram_percentage=0
peak_cpu_usage=0
peak_time=""
start_time=$(date +%s)
last_rotation=$(date +%s)

while true; do
    current_time=$(date +%s)
    current_ram_usage=$(get_ram_usage)
    current_ram_percentage=$(get_ram_percentage)
    current_cpu_usage=$(get_cpu_usage)
    
    # Update peak if current usage is higher
    if (( $(echo "$current_ram_usage > $peak_ram_usage" | bc -l) )); then
        peak_ram_usage=$current_ram_usage
        peak_ram_percentage=$current_ram_percentage
        peak_time=$(date '+%Y-%m-%d %H:%M:%S')
    fi
    
    if (( $(echo "$current_cpu_usage > $peak_cpu_usage" | bc -l) )); then
        peak_cpu_usage=$current_cpu_usage
        if [ -z "$peak_time" ]; then
            peak_time=$(date '+%Y-%m-%d %H:%M:%S')
        fi
    fi
    
    # Check if it's time to generate report (every 20 minutes)
    if (( current_time - start_time >= REPORT_INTERVAL )); then
        generate_peak_report "$peak_time" "$peak_ram_usage" "$peak_ram_percentage" "$peak_cpu_usage"
        
        # Reset peak values for next interval
        peak_ram_usage=0
        peak_ram_percentage=0
        peak_cpu_usage=0
        peak_time=""
        start_time=$current_time
    fi
    
    # Check if it's time to rotate logs (every 5 minutes)
    if (( current_time - last_rotation >= 300 )); then
        rotate_logs
        last_rotation=$current_time
    fi
    
    sleep $CHECK_INTERVAL
done 