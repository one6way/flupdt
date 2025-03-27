#!/bin/bash

# Configuration
LOG_DIR="/var/log"
BACKUP_DIR="/var/log/backup_$(date +%Y%m%d_%H%M%S)"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Function to anonymize file
anonymize_file() {
    local file=$1
    echo "Processing $file..."
    
    # Create backup
    cp "$file" "$BACKUP_DIR/"
    
    # Replace specific DNS and IP
    sed -i 's/npp-ml01-eps/srv-prom01-flex/g' "$file"
    sed -i 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/192.168.0.1/g' "$file"
}

# Main script
echo "Starting log anonymization..."

# Process all log files
find "$LOG_DIR" -type f -name "*.log" | while read -r file; do
    anonymize_file "$file"
done

echo "Log anonymization completed. Backups saved in $BACKUP_DIR" 