#!/bin/bash

# Configuration
LOG_FILE="/var/log/system_monitor.log"
SCRIPT_LOG_FILE="script_operation.log"
EMAIL_TO="your-email@example.com"  # Change this to your email
CHECK_INTERVAL=300  # 5 minutes in seconds
EMAIL_INTERVAL=1800  # 30 minutes in seconds
LOG_RETENTION_HOURS=2  # Keep logs for 2 hours
ENABLE_LOG_CLEANUP=true  # Set to false to disable log cleanup

# Directories to monitor for existence
MONITOR_DIRS=("/opt/fl/flexloader/run/apl_service" "/opt/fl/flexloader/run/target.init-service" "/opt/fl/flexloader/run/mata.init-service")

# Services to monitor for detailed statistics
# Format: "Service Name|Process Pattern|Description"
# Process Pattern can be:
# - Exact process name
# - Regular expression
# - Command line pattern
MONITOR_SERVICES=(
    "APL Service|apl_service|APL Service Process"
    "Target Service|target.init-service|Target Service Process"
    "Mata Service|mata.init-service|Mata Service Process"
    "Java Processes|java|Java Virtual Machine Processes"
    "Database|postgres|PostgreSQL Database"
    "Web Server|nginx|Nginx Web Server"
    "System Services|systemd|System Service Manager"
)

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
    local current_time=$(date +%s)
    local retention_seconds=$((LOG_RETENTION_HOURS * 3600))
    local current_date=$(get_current_date)
    
    # Rotate system monitor log if it exists and is old
    if [ -f "$LOG_FILE" ]; then
        local log_time=$(stat -c %Y "$LOG_FILE")
        if [ $((current_time - log_time)) -gt $retention_seconds ]; then
            log_script_operation "Rotating old system monitor log"
            mv "$LOG_FILE" "${LOG_FILE}.${current_date}"
            touch "$LOG_FILE"
            chmod 644 "$LOG_FILE"
        fi
    fi
    
    # Rotate script operation log if it exists and is old
    if [ -f "$SCRIPT_LOG_FILE" ]; then
        local log_time=$(stat -c %Y "$SCRIPT_LOG_FILE")
        if [ $((current_time - log_time)) -gt $retention_seconds ]; then
            log_script_operation "Rotating old script operation log"
            mv "$SCRIPT_LOG_FILE" "${SCRIPT_LOG_FILE}.${current_date}"
            touch "$SCRIPT_LOG_FILE"
            chmod 644 "$SCRIPT_LOG_FILE"
        fi
    fi
    
    # Clean up old rotated logs (keep last 5)
    for log_type in "$LOG_FILE" "$SCRIPT_LOG_FILE"; do
        if [ -f "$log_type" ]; then
            ls -t "${log_type}."* 2>/dev/null | tail -n +6 | xargs -r rm
        fi
    done
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
    echo -e "\n=== Detailed RAM Usage Report at $(get_timestamp) ===" >> "$LOG_FILE"
    
    # Overall system memory status
    echo -e "\n=== System Memory Overview ===" >> "$LOG_FILE"
    free -h >> "$LOG_FILE"
    
    # Detailed memory information
    echo -e "\n=== Detailed Memory Information ===" >> "$LOG_FILE"
    cat /proc/meminfo >> "$LOG_FILE"
    
    # Swap usage
    echo -e "\n=== Swap Usage ===" >> "$LOG_FILE"
    swapon --show >> "$LOG_FILE"
    
    # Process memory statistics with detailed information
    echo -e "\n=== Detailed Process Statistics ===" >> "$LOG_FILE"
    echo "Format: PID | PPID | User | %CPU | %MEM | RSS | VSZ | Command | Start Time | State | Priority | Threads | CPU Affinity" >> "$LOG_FILE"
    ps -eo pid,ppid,user,%cpu,%mem,rss,vsz,cmd,start,stat,pri,nlwp,psr --sort=-%mem | \
    awk '{printf "%-8s %-8s %-10s %-6s %-6s %-10s %-10s %-30s %-20s %-6s %-8s %-8s %-10s\n", 
         $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13}' >> "$LOG_FILE"
    
    # Process tree with memory usage and command line arguments
    echo -e "\n=== Process Tree with Memory Usage and Arguments ===" >> "$LOG_FILE"
    ps -eo pid,ppid,%mem,rss,cmd,args --forest >> "$LOG_FILE"
    
    # Memory usage by user with process count
    echo -e "\n=== Memory Usage by User with Process Count ===" >> "$LOG_FILE"
    ps aux | awk '{sum[$1] += $4; count[$1]++} END {for (user in sum) print user, sum[user]"%", count[user]" processes"}' | sort -k2 -nr >> "$LOG_FILE"
    
    # Detailed process information for monitored services
    echo -e "\n=== Detailed Information for Monitored Services ===" >> "$LOG_FILE"
    for service in "${MONITOR_SERVICES[@]}"; do
        IFS='|' read -r service_name pattern description <<< "$service"
        echo -e "\nService: $service_name ($description)" >> "$LOG_FILE"
        
        # Try different methods to find the process
        pids=$(pgrep -f "$pattern" 2>/dev/null)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                echo -e "\nProcess ID: $pid" >> "$LOG_FILE"
                echo "Command Line: $(ps -p $pid -o cmd=)" >> "$LOG_FILE"
                echo "Memory Usage: $(ps -p $pid -o %mem,rss,vsz=)" >> "$LOG_FILE"
                echo "CPU Usage: $(ps -p $pid -o %cpu=)" >> "$LOG_FILE"
                echo "Start Time: $(ps -p $pid -o start=)" >> "$LOG_FILE"
                echo "User: $(ps -p $pid -o user=)" >> "$LOG_FILE"
                echo "Threads: $(ps -p $pid -o nlwp=)" >> "$LOG_FILE"
                echo "Priority: $(ps -p $pid -o pri=)" >> "$LOG_FILE"
                echo "CPU Affinity: $(ps -p $pid -o psr=)" >> "$LOG_FILE"
                echo "Status: $(ps -p $pid -o stat=)" >> "$LOG_FILE"
                echo "Parent Process: $(ps -p $pid -o ppid=)" >> "$LOG_FILE"
                echo "Open Files: $(lsof -p $pid | wc -l)" >> "$LOG_FILE"
                
                # Additional process information
                echo "Process Environment:" >> "$LOG_FILE"
                cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep -v '^$' >> "$LOG_FILE"
                
                # Process limits
                echo "Process Limits:" >> "$LOG_FILE"
                cat /proc/$pid/limits 2>/dev/null >> "$LOG_FILE"
            done
        else
            echo "Service is not running" >> "$LOG_FILE"
            # Check if service exists in systemd
            if systemctl list-unit-files | grep -q "$pattern.service"; then
                echo "Service exists in systemd but is not running" >> "$LOG_FILE"
                systemctl status "$pattern.service" 2>/dev/null >> "$LOG_FILE"
            fi
        fi
    done
    
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
    
    # System load and uptime
    echo -e "\n=== System Load and Uptime ===" >> "$LOG_FILE"
    uptime >> "$LOG_FILE"
    
    # Process limits
    echo -e "\n=== Process Resource Limits ===" >> "$LOG_FILE"
    ulimit -a >> "$LOG_FILE"
    
    echo "=====================================" >> "$LOG_FILE"
    log_script_operation "RAM usage and process statistics check completed"
}

# Function to check system logs for OOM and process termination
check_system_logs() {
    local process_name=$1
    local last_check=$2
    
    log_script_operation "Checking system logs for process: $process_name"
    echo "[$(get_timestamp)] Checking system logs for $process_name since $last_check" >> "$LOG_FILE"
    
    # Check for all OOM killed processes
    echo -e "\n=== OOM Killed Processes (Last 24 hours) ===" >> "$LOG_FILE"
    dmesg | grep -i "out of memory" | grep -A 5 "since $last_check" >> "$LOG_FILE"
    
    # Get detailed information about killed processes
    echo -e "\n=== Detailed Information About Killed Processes ===" >> "$LOG_FILE"
    dmesg | grep -i "killed process" | grep -A 3 "since $last_check" | while read -r line; do
        if [[ $line =~ "killed process" ]]; then
            pid=$(echo "$line" | grep -oP "pid \K\d+")
            name=$(echo "$line" | grep -oP "process \K\w+")
            echo -e "\nProcess Killed:" >> "$LOG_FILE"
            echo "PID: $pid" >> "$LOG_FILE"
            echo "Name: $name" >> "$LOG_FILE"
            
            # Get process details from journal
            echo "Process Details:" >> "$LOG_FILE"
            journalctl --since "$last_check" | grep "pid=$pid" | grep -i "killed\|terminated\|oom" >> "$LOG_FILE"
            
            # Get memory state at time of kill
            echo "Memory State:" >> "$LOG_FILE"
            free -h >> "$LOG_FILE"
        fi
    done
    
    # Check system journal for process termination and system events
    echo -e "\n=== System Journal Events ===" >> "$LOG_FILE"
    journalctl --since "$last_check" | grep -i "killed\|terminated\|oom\|failed\|error" >> "$LOG_FILE"
    
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

# Function to check for OOM events
check_oom_events() {
    local last_check=$(date -d "24 hours ago" "+%Y-%m-%d %H:%M:%S")
    
    echo -e "\n=== CRITICAL: OOM EVENTS REPORT (Last 24 hours) ===" >> "$LOG_FILE"
    echo "Generated at: $(get_timestamp)" >> "$LOG_FILE"
    echo "===================================================" >> "$LOG_FILE"
    
    # Get all OOM killed processes from dmesg
    echo -e "\n[CRITICAL] Processes Killed by OOM Killer:" >> "$LOG_FILE"
    dmesg | grep -i "out of memory" | while read -r line; do
        # Extract timestamp from dmesg line
        timestamp=$(echo "$line" | grep -oP "\[.*?\]")
        if [ ! -z "$timestamp" ]; then
            # Convert dmesg timestamp to date
            dmesg_date=$(date -d "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            if [ ! -z "$dmesg_date" ]; then
                # Compare with last_check
                if [[ "$dmesg_date" > "$last_check" ]]; then
                    echo -e "\n[CRITICAL] OOM Event Detected at $dmesg_date:" >> "$LOG_FILE"
                    echo "----------------------------------------" >> "$LOG_FILE"
                    
                    # Extract process information
                    pid=$(echo "$line" | grep -oP "pid \K\d+")
                    name=$(echo "$line" | grep -oP "process \K\w+")
                    memory=$(echo "$line" | grep -oP "total-vm:\K[^,]+")
                    rss=$(echo "$line" | grep -oP "rss:\K[^,]+")
                    
                    echo "Process Details:" >> "$LOG_FILE"
                    echo "PID: $pid" >> "$LOG_FILE"
                    echo "Name: $name" >> "$LOG_FILE"
                    echo "Total Virtual Memory: $memory" >> "$LOG_FILE"
                    echo "Resident Set Size: $rss" >> "$LOG_FILE"
                    
                    # Get process details from ps if process still exists
                    if ps -p "$pid" > /dev/null 2>&1; then
                        echo "Current Process Status:" >> "$LOG_FILE"
                        ps -p "$pid" -o pid,ppid,user,%cpu,%mem,rss,vsz,cmd,start,stat >> "$LOG_FILE"
                    fi
                    
                    # Get memory state at time of kill
                    echo -e "\nSystem Memory State at Kill:" >> "$LOG_FILE"
                    free -h >> "$LOG_FILE"
                    
                    # Get system load
                    echo -e "\nSystem Load at Kill:" >> "$LOG_FILE"
                    uptime >> "$LOG_FILE"
                    
                    # Get process details from journal
                    echo -e "\nProcess Termination Details:" >> "$LOG_FILE"
                    journalctl --since "$dmesg_date" --until "$(date '+%Y-%m-%d %H:%M:%S')" | grep "pid=$pid" | grep -i "killed\|terminated\|oom" >> "$LOG_FILE"
                    
                    # Get memory pressure events around the time of kill
                    echo -e "\nMemory Pressure Events:" >> "$LOG_FILE"
                    journalctl --since "$(date -d "$dmesg_date - 5 minutes" '+%Y-%m-%d %H:%M:%S')" --until "$(date -d "$dmesg_date + 5 minutes" '+%Y-%m-%d %H:%M:%S')" | grep -i "memory pressure\|low memory\|swap\|out of memory" >> "$LOG_FILE"
                    
                    echo "----------------------------------------" >> "$LOG_FILE"
                fi
            fi
        fi
    done
    
    # Additional check for killed processes in system logs
    echo -e "\n[CRITICAL] Additional Process Terminations:" >> "$LOG_FILE"
    journalctl --since "$last_check" | grep -i "killed process" | while read -r line; do
        if [[ $line =~ "killed process" ]]; then
            echo -e "\nProcess Termination Event:" >> "$LOG_FILE"
            echo "$line" >> "$LOG_FILE"
            pid=$(echo "$line" | grep -oP "pid \K\d+")
            if [ ! -z "$pid" ]; then
                echo "Process Details:" >> "$LOG_FILE"
                ps -p "$pid" -o pid,ppid,user,%cpu,%mem,rss,vsz,cmd,start,stat 2>/dev/null >> "$LOG_FILE"
            fi
        fi
    done
    
    # Get current system resource usage
    echo -e "\nCurrent System Resource Usage:" >> "$LOG_FILE"
    echo "Memory Limits:" >> "$LOG_FILE"
    ulimit -a >> "$LOG_FILE"
    echo -e "\nCurrent Memory Pressure:" >> "$LOG_FILE"
    cat /proc/pressure/memory >> "$LOG_FILE"
    
    echo -e "\n===================================================" >> "$LOG_FILE"
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

# Function to create OOM events summary
create_oom_summary() {
    local last_check=$(date -d "24 hours ago" "+%Y-%m-%d %H:%M:%S")
    
    echo -e "\n=== CRITICAL: OOM EVENTS SUMMARY (Last 24 hours) ===" >> "$LOG_FILE"
    echo "Generated at: $(get_timestamp)" >> "$LOG_FILE"
    echo "===================================================" >> "$LOG_FILE"
    
    # Get all OOM killed processes from dmesg
    echo -e "\n[CRITICAL] Processes Killed by OOM Killer:" >> "$LOG_FILE"
    dmesg | grep -i "out of memory" | while read -r line; do
        # Extract timestamp from dmesg line
        timestamp=$(echo "$line" | grep -oP "\[.*?\]")
        if [ ! -z "$timestamp" ]; then
            # Convert dmesg timestamp to date
            dmesg_date=$(date -d "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            if [ ! -z "$dmesg_date" ]; then
                # Compare with last_check
                if [[ "$dmesg_date" > "$last_check" ]]; then
                    echo -e "\n[CRITICAL] OOM Event Detected at $dmesg_date:" >> "$LOG_FILE"
                    echo "----------------------------------------" >> "$LOG_FILE"
                    
                    # Extract process information
                    pid=$(echo "$line" | grep -oP "pid \K\d+")
                    name=$(echo "$line" | grep -oP "process \K\w+")
                    memory=$(echo "$line" | grep -oP "total-vm:\K[^,]+")
                    rss=$(echo "$line" | grep -oP "rss:\K[^,]+")
                    
                    echo "Process Details:" >> "$LOG_FILE"
                    echo "PID: $pid" >> "$LOG_FILE"
                    echo "Name: $name" >> "$LOG_FILE"
                    echo "Total Virtual Memory: $memory" >> "$LOG_FILE"
                    echo "Resident Set Size: $rss" >> "$LOG_FILE"
                    
                    # Get process details from ps if process still exists
                    if ps -p "$pid" > /dev/null 2>&1; then
                        echo "Current Process Status:" >> "$LOG_FILE"
                        ps -p "$pid" -o pid,ppid,user,%cpu,%mem,rss,vsz,cmd,start,stat >> "$LOG_FILE"
                    fi
                    
                    # Get memory state at time of kill
                    echo -e "\nSystem Memory State at Kill:" >> "$LOG_FILE"
                    free -h >> "$LOG_FILE"
                    
                    # Get system load
                    echo -e "\nSystem Load at Kill:" >> "$LOG_FILE"
                    uptime >> "$LOG_FILE"
                    
                    # Get process details from journal
                    echo -e "\nProcess Termination Details:" >> "$LOG_FILE"
                    journalctl --since "$dmesg_date" --until "$(date '+%Y-%m-%d %H:%M:%S')" | grep "pid=$pid" | grep -i "killed\|terminated\|oom" >> "$LOG_FILE"
                    
                    # Get memory pressure events around the time of kill
                    echo -e "\nMemory Pressure Events:" >> "$LOG_FILE"
                    journalctl --since "$(date -d "$dmesg_date - 5 minutes" '+%Y-%m-%d %H:%M:%S')" --until "$(date -d "$dmesg_date + 5 minutes" '+%Y-%m-%d %H:%M:%S')" | grep -i "memory pressure\|low memory\|swap\|out of memory" >> "$LOG_FILE"
                    
                    echo "----------------------------------------" >> "$LOG_FILE"
                fi
            fi
        fi
    done
    
    # Check system journal for additional OOM events
    echo -e "\n[CRITICAL] Additional OOM Events from System Journal:" >> "$LOG_FILE"
    journalctl --since "$last_check" | grep -i "out of memory\|killed process" | while read -r line; do
        if [[ $line =~ "killed process" ]] || [[ $line =~ "out of memory" ]]; then
            echo -e "\nEvent:" >> "$LOG_FILE"
            echo "$line" >> "$LOG_FILE"
            pid=$(echo "$line" | grep -oP "pid \K\d+")
            if [ ! -z "$pid" ]; then
                echo "Process Details:" >> "$LOG_FILE"
                ps -p "$pid" -o pid,ppid,user,%cpu,%mem,rss,vsz,cmd,start,stat 2>/dev/null >> "$LOG_FILE"
            fi
        fi
    done
    
    # Get current system resource usage
    echo -e "\nCurrent System Resource Usage:" >> "$LOG_FILE"
    echo "Memory Limits:" >> "$LOG_FILE"
    ulimit -a >> "$LOG_FILE"
    echo -e "\nCurrent Memory Pressure:" >> "$LOG_FILE"
    cat /proc/pressure/memory >> "$LOG_FILE"
    
    echo -e "\n===================================================" >> "$LOG_FILE"
}

# Function to collect detailed information about killed processes
collect_killed_process_info() {
    local last_check=$(date -d "24 hours ago" "+%Y-%m-%d %H:%M:%S")
    
    echo -e "\n=== DETAILED KILLED PROCESSES REPORT (Last 24 hours) ===" >> "$LOG_FILE"
    echo "Generated at: $(get_timestamp)" >> "$LOG_FILE"
    echo "===================================================" >> "$LOG_FILE"
    
    # Check dmesg for OOM kills (without time filtering first)
    echo -e "\n[CRITICAL] OOM Killer Events from dmesg:" >> "$LOG_FILE"
    dmesg | grep -i "out of memory" | while read -r line; do
        echo -e "\nOOM Event:" >> "$LOG_FILE"
        echo "$line" >> "$LOG_FILE"
        
        # Extract process information
        pid=$(echo "$line" | grep -oP "pid \K\d+")
        if [ ! -z "$pid" ]; then
            echo "Process Details:" >> "$LOG_FILE"
            echo "PID: $pid" >> "$LOG_FILE"
            echo "Name: $(echo "$line" | grep -oP "process \K\w+")" >> "$LOG_FILE"
            echo "Memory Usage: $(echo "$line" | grep -oP "total-vm:\K[^,]+")" >> "$LOG_FILE"
            echo "RSS: $(echo "$line" | grep -oP "rss:\K[^,]+")" >> "$LOG_FILE"
            
            # Try to get additional process info
            if [ -d "/proc/$pid" ]; then
                echo "Executable Path: $(readlink -f /proc/$pid/exe 2>/dev/null)" >> "$LOG_FILE"
                echo "Working Directory: $(readlink -f /proc/$pid/cwd 2>/dev/null)" >> "$LOG_FILE"
                echo "Command Line: $(cat /proc/$pid/cmdline 2>/dev/null)" >> "$LOG_FILE"
                echo "Environment Variables:" >> "$LOG_FILE"
                cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' >> "$LOG_FILE"
                echo "Process Status:" >> "$LOG_FILE"
                cat /proc/$pid/status 2>/dev/null >> "$LOG_FILE"
                echo "Process Limits:" >> "$LOG_FILE"
                cat /proc/$pid/limits 2>/dev/null >> "$LOG_FILE"
                echo "Process Maps:" >> "$LOG_FILE"
                cat /proc/$pid/maps 2>/dev/null >> "$LOG_FILE"
            fi
            
            # Get process tree
            echo "Process Tree:" >> "$LOG_FILE"
            pstree -p $pid 2>/dev/null >> "$LOG_FILE"
            
            # Get process owner and group
            echo "Process Owner:" >> "$LOG_FILE"
            ps -p $pid -o user,group,uid,gid 2>/dev/null >> "$LOG_FILE"
            
            # Get process start time and runtime
            echo "Process Start Time and Runtime:" >> "$LOG_FILE"
            ps -p $pid -o pid,start,etime,cmd 2>/dev/null >> "$LOG_FILE"
            
            # Get process resource usage
            echo "Process Resource Usage:" >> "$LOG_FILE"
            ps -p $pid -o pid,ppid,%cpu,%mem,rss,vsz,cmd 2>/dev/null >> "$LOG_FILE"
            
            # Get process open files
            echo "Process Open Files:" >> "$LOG_FILE"
            lsof -p $pid 2>/dev/null >> "$LOG_FILE"
            
            # Get process network connections
            echo "Process Network Connections:" >> "$LOG_FILE"
            netstat -tunp 2>/dev/null | grep $pid >> "$LOG_FILE"
            
            # Get process system calls
            echo "Process System Calls:" >> "$LOG_FILE"
            strace -p $pid 2>/dev/null | head -n 20 >> "$LOG_FILE"
        fi
    done
    
    # Check system journal (without time filtering first)
    echo -e "\n[CRITICAL] Process Terminations from System Journal:" >> "$LOG_FILE"
    journalctl | grep -i "killed process\|out of memory" | while read -r line; do
        if [[ $line =~ "killed process" ]] || [[ $line =~ "out of memory" ]]; then
            echo -e "\nEvent:" >> "$LOG_FILE"
            echo "$line" >> "$LOG_FILE"
            pid=$(echo "$line" | grep -oP "pid \K\d+")
            if [ ! -z "$pid" ]; then
                echo "Process Details:" >> "$LOG_FILE"
                # Try to get process info from proc if still exists
                if [ -d "/proc/$pid" ]; then
                    echo "Executable Path: $(readlink -f /proc/$pid/exe 2>/dev/null)" >> "$LOG_FILE"
                    echo "Working Directory: $(readlink -f /proc/$pid/cwd 2>/dev/null)" >> "$LOG_FILE"
                    echo "Command Line: $(cat /proc/$pid/cmdline 2>/dev/null)" >> "$LOG_FILE"
                    echo "Process Status:" >> "$LOG_FILE"
                    cat /proc/$pid/status 2>/dev/null >> "$LOG_FILE"
                fi
            fi
        fi
    done
    
    # Check system logs
    echo -e "\n[CRITICAL] Process Terminations from System Logs:" >> "$LOG_FILE"
    if [ -f "/var/log/syslog" ]; then
        grep -i "killed process\|out of memory" /var/log/syslog >> "$LOG_FILE"
    fi
    
    # Check audit logs if available
    if command -v ausearch >/dev/null 2>&1; then
        echo -e "\n[CRITICAL] Process Terminations from Audit Logs:" >> "$LOG_FILE"
        ausearch -ts recent -k kill >> "$LOG_FILE"
    fi
    
    # Check for deleted processes in proc
    echo -e "\n[CRITICAL] Recently Deleted Processes:" >> "$LOG_FILE"
    ls -l /proc/*/exe 2>/dev/null | grep -i "deleted" >> "$LOG_FILE"
    
    # Check systemd logs for service terminations
    echo -e "\n[CRITICAL] Service Terminations from Systemd:" >> "$LOG_FILE"
    journalctl -u systemd-journald | grep -i "killed process" >> "$LOG_FILE"
    
    # Check application logs if they exist
    echo -e "\n[CRITICAL] Application Logs:" >> "$LOG_FILE"
    for log_file in /var/log/*.log; do
        if [ -f "$log_file" ]; then
            echo "Checking $log_file:" >> "$LOG_FILE"
            grep -i "killed process\|out of memory" "$log_file" | tail -n 10 >> "$LOG_FILE"
        fi
    done
    
    # Additional check for OOM events in kernel ring buffer
    echo -e "\n[CRITICAL] Additional OOM Events from Kernel Ring Buffer:" >> "$LOG_FILE"
    dmesg -T | grep -i "out of memory" >> "$LOG_FILE"
    
    echo -e "\n===================================================" >> "$LOG_FILE"
}

# Main monitoring loop
last_email_time=0

while true; do
    current_time=$(date +%s)
    
    # Clean old logs
    clean_old_logs
    
    # Create OOM events summary at the beginning of the log
    create_oom_summary
    
    # Collect detailed information about killed processes
    collect_killed_process_info
    
    # Check RAM usage every 5 minutes
    check_ram_usage
    
    # Check for OOM events
    check_oom_events
    
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