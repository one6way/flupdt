#!/bin/bash

# Configuration
LOG_DIR="/var/log/ram_monitor"
LOG_FILE="$LOG_DIR/ram_peak.log"
PEAK_FILE="$LOG_DIR/absolute_peaks.txt"
MONITOR_INTERVAL=60  # seconds
REPORT_INTERVAL=1200  # 20 minutes
LOG_ROTATE_INTERVAL=7200  # 2 hours
MAX_ARCHIVES=36  # keep last 36 archives (3 days with 2-hour rotation)

# Function to create log directory if it doesn't exist
create_log_dir() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
        log_message "Created log directory: $LOG_DIR"
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

    # Округляем значения до целых чисел
    current_ram=$(printf "%.0f" "$current_ram")
    current_ram_percent=$(printf "%.0f" "$current_ram_percent")
    current_cpu=$(printf "%.0f" "$current_cpu")
    RAM_PEAK=$(printf "%.0f" "$RAM_PEAK")
    RAM_PEAK_PERCENT=$(printf "%.0f" "$RAM_PEAK_PERCENT")
    CPU_PEAK=$(printf "%.0f" "$CPU_PEAK")

    # Проверяем и обновляем пиковые значения
    if [ "$current_ram" -gt "$RAM_PEAK" ]; then
        RAM_PEAK=$current_ram
        updated=true
    fi

    if [ "$current_ram_percent" -gt "$RAM_PEAK_PERCENT" ]; then
        RAM_PEAK_PERCENT=$current_ram_percent
        updated=true
    fi

    if [ "$current_cpu" -gt "$CPU_PEAK" ]; then
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
    local old_log="$LOG_FILE.$current_date.$current_time.gz"
    
    # Compress the current log
    if [ -f "$LOG_FILE" ]; then
        gzip -c "$LOG_FILE" > "$old_log"
        rm -f "$LOG_FILE"
        log_message "Rotated log file to $old_log"
    fi
    
    # Create new empty log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # Delete old archives, keeping only the last MAX_ARCHIVES (3 days)
    cd "$LOG_DIR" || exit
    ls -t ram_peak.log.*.gz 2>/dev/null | tail -n +$((MAX_ARCHIVES + 1)) | xargs -r rm -f
    log_message "Cleaned up old log archives, keeping last $MAX_ARCHIVES (3 days of logs)"
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

# Main monitoring loop
main() {
    create_log_dir
    init_peak_file
    
    local last_report=0
    local last_rotate=0
    local current_time
    
    echo "Starting RAM and CPU monitoring..."
    echo "Monitor interval: $MONITOR_INTERVAL seconds"
    echo "Report interval: $REPORT_INTERVAL seconds"
    echo "Log rotation interval: $LOG_ROTATE_INTERVAL seconds"
    echo "Maximum archives to keep: $MAX_ARCHIVES"
    
    while true; do
        current_time=$(date +%s)
        
        # Check if it's time to rotate logs (every 2 hours)
        if [ $((current_time - last_rotate)) -ge $LOG_ROTATE_INTERVAL ]; then
            echo "[$(date '+%H:%M:%S')] Rotating logs..."
            rotate_logs
            last_rotate=$current_time
        fi
        
        # Get current values
        get_ram_usage
        get_cpu_usage
        
        # Update absolute peaks
        update_absolute_peaks "$ram_usage" "$ram_percent" "$cpu_usage"
        
        # Check if it's time to generate report
        if [ $((current_time - last_report)) -ge $REPORT_INTERVAL ]; then
            generate_peak_report
            last_report=$current_time
            echo "[$(date '+%H:%M:%S')] Generated new peak report"
        fi
        
        # Log current values
        log_message "Current values - RAM: ${ram_usage}MB (${ram_percent}%), CPU: ${cpu_usage}%"
        
        sleep $MONITOR_INTERVAL
    done
}

# Main script
main 