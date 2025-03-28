#!/bin/bash

# Configuration
LOG_DIR="/var/log/ram_monitor"
LOG_FILE="$LOG_DIR/ram_peak.log"
PEAK_FILE="$LOG_DIR/absolute_peaks.txt"
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

# Function to initialize peak file if it doesn't exist
init_peak_file() {
    if [ ! -f "$PEAK_FILE" ]; then
        echo "RAM_PEAK=0" > "$PEAK_FILE"
        echo "RAM_PEAK_PERCENT=0" >> "$PEAK_FILE"
        echo "CPU_PEAK=0" >> "$PEAK_FILE"
        echo "PEAK_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$PEAK_FILE"
        chmod 644 "$PEAK_FILE"
        log_message "Created new peak file with initial values"
    fi
}

# Function to get absolute peak values
get_absolute_peaks() {
    if [ -f "$PEAK_FILE" ]; then
        source "$PEAK_FILE"
    else
        RAM_PEAK=0
        RAM_PEAK_PERCENT=0
        CPU_PEAK=0
        PEAK_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    fi
}

# Function to update absolute peak values
update_absolute_peaks() {
    local current_ram=$1
    local current_ram_percent=$2
    local current_cpu=$3
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local updated=false

    # Проверяем и обновляем пиковые значения
    if [ "$(echo "$current_ram > $RAM_PEAK" | bc)" -eq 1 ]; then
        RAM_PEAK=$current_ram
        updated=true
    fi

    if [ "$(echo "$current_ram_percent > $RAM_PEAK_PERCENT" | bc)" -eq 1 ]; then
        RAM_PEAK_PERCENT=$current_ram_percent
        updated=true
    fi

    if [ "$(echo "$current_cpu > $CPU_PEAK" | bc)" -eq 1 ]; then
        CPU_PEAK=$current_cpu
        updated=true
    fi

    # Если были обновления, сохраняем новые значения
    if [ "$updated" = true ]; then
        PEAK_TIME=$current_time
        echo "RAM_PEAK=$RAM_PEAK" > "$PEAK_FILE"
        echo "RAM_PEAK_PERCENT=$RAM_PEAK_PERCENT" >> "$PEAK_FILE"
        echo "CPU_PEAK=$CPU_PEAK" >> "$PEAK_FILE"
        echo "PEAK_TIME=$PEAK_TIME" >> "$PEAK_FILE"
        log_message "New absolute peak values: RAM=${RAM_PEAK}MB (${RAM_PEAK_PERCENT}%), CPU=${CPU_PEAK}% at $PEAK_TIME"
    fi
}

# Function to rotate log files
rotate_logs() {
    local current_date=$(date '+%Y-%m-%d')
    local current_time=$(date '+%H-%M-%S')
    local old_log="$LOG_FILE.$current_date.$current_time"
    
    # Always rotate the current log file
    if [ -f "$LOG_FILE" ]; then
        mv "$LOG_FILE" "$old_log"
        gzip "$old_log"
        log_message "Rotated log file to $old_log.gz"
        # Create new empty log file
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
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
    
    get_absolute_peaks
    
    log_message "=== System Peak Report for $(date '+%Y-%m-%d %H:%M:%S') ==="
    log_message "Current Interval Peaks:"
    log_message "  RAM: ${peak_ram_usage}MB (${peak_ram_percentage}%)"
    log_message "  CPU: ${peak_cpu_usage}%"
    log_message "  Time: $peak_time"
    
    log_message "Absolute All-Time Peaks:"
    log_message "  RAM: ${RAM_PEAK}MB (${RAM_PEAK_PERCENT}%)"
    log_message "  CPU: ${CPU_PEAK}%"
    log_message "  Time: $PEAK_TIME"
    
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
init_peak_file
echo "System Peak Monitor Started"
log_message "System Peak Monitor Started"
echo "Monitoring interval: $CHECK_INTERVAL seconds"
echo "Report interval: $REPORT_INTERVAL seconds"
echo "Log rotation interval: 300 seconds"
echo "Log directory: $LOG_DIR"
echo "Current time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------"

# Initialize variables
peak_ram_usage=0
peak_ram_percentage=0
peak_cpu_usage=0
peak_time=""
start_time=$(date +%s)
last_rotation=$(date +%s)
check_count=0

while true; do
    current_time=$(date +%s)
    current_ram_usage=$(get_ram_usage)
    current_ram_percentage=$(get_ram_percentage)
    current_cpu_usage=$(get_cpu_usage)
    
    # Update absolute peaks
    update_absolute_peaks "$current_ram_usage" "$current_ram_percentage" "$current_cpu_usage" "$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Update interval peak if current usage is higher
    if (( $(echo "$current_ram_usage > $peak_ram_usage" | bc -l) )); then
        peak_ram_usage=$current_ram_usage
        peak_ram_percentage=$current_ram_percentage
        peak_time=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$(date '+%H:%M:%S')] New RAM peak: ${peak_ram_usage}MB (${peak_ram_percentage}%)"
    fi
    
    if (( $(echo "$current_cpu_usage > $peak_cpu_usage" | bc -l) )); then
        peak_cpu_usage=$current_cpu_usage
        if [ -z "$peak_time" ]; then
            peak_time=$(date '+%Y-%m-%d %H:%M:%S')
        fi
        echo "[$(date '+%H:%M:%S')] New CPU peak: ${peak_cpu_usage}%"
    fi
    
    # Check if it's time to generate report (every 20 minutes)
    if (( current_time - start_time >= REPORT_INTERVAL )); then
        echo "----------------------------------------"
        echo "[$(date '+%H:%M:%S')] Generating report..."
        generate_peak_report "$peak_time" "$peak_ram_usage" "$peak_ram_percentage" "$peak_cpu_usage"
        echo "[$(date '+%H:%M:%S')] Report generated"
        
        # Reset interval peak values for next interval
        peak_ram_usage=0
        peak_ram_percentage=0
        peak_cpu_usage=0
        peak_time=""
        start_time=$current_time
        echo "----------------------------------------"
    fi
    
    # Check if it's time to rotate logs (every 5 minutes)
    if (( current_time - last_rotation >= 300 )); then
        echo "[$(date '+%H:%M:%S')] Rotating logs..."
        rotate_logs
        last_rotation=$current_time
        echo "[$(date '+%H:%M:%S')] Logs rotated"
    fi
    
    # Print current status every 5 checks
    ((check_count++))
    if [ $((check_count % 5)) -eq 0 ]; then
        echo "[$(date '+%H:%M:%S')] Current status - RAM: ${current_ram_usage}MB (${current_ram_percentage}%), CPU: ${current_cpu_usage}%"
    fi
    
    sleep $CHECK_INTERVAL
done 