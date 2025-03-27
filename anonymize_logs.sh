#!/bin/bash

# Configuration
LOG_DIR="/var/log"
TEMP_DIR="/tmp/anonymize_logs"
IP_MAP_FILE="$TEMP_DIR/ip_map.txt"
DNS_MAP_FILE="$TEMP_DIR/dns_map.txt"
BACKUP_DIR="/var/log/backup_$(date +%Y%m%d_%H%M%S)"

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Function to generate random IP address
generate_random_ip() {
    echo "192.168.$((RANDOM % 254 + 1)).$((RANDOM % 254 + 1))"
}

# Function to generate random DNS name
generate_random_dns() {
    local domains=("example.com" "test.net" "internal.org" "local.domain")
    local domain=${domains[$RANDOM % ${#domains[@]}]}
    local name_length=$((RANDOM % 10 + 5))
    local name=$(cat /dev/urandom | tr -dc 'a-z' | fold -w $name_length | head -n 1)
    echo "$name.$domain"
}

# Function to create IP mapping
create_ip_mapping() {
    local ip=$1
    if [ ! -f "$IP_MAP_FILE" ]; then
        touch "$IP_MAP_FILE"
    fi
    if ! grep -q "^$ip|" "$IP_MAP_FILE"; then
        echo "$ip|$(generate_random_ip)" >> "$IP_MAP_FILE"
    fi
    grep "^$ip|" "$IP_MAP_FILE" | cut -d'|' -f2
}

# Function to create DNS mapping
create_dns_mapping() {
    local dns=$1
    if [ ! -f "$DNS_MAP_FILE" ]; then
        touch "$DNS_MAP_FILE"
    fi
    if ! grep -q "^$dns|" "$DNS_MAP_FILE"; then
        echo "$dns|$(generate_random_dns)" >> "$DNS_MAP_FILE"
    fi
    grep "^$dns|" "$DNS_MAP_FILE" | cut -d'|' -f2
}

# Function to anonymize file
anonymize_file() {
    local file=$1
    local temp_file="$TEMP_DIR/$(basename "$file")"
    
    echo "Processing $file..."
    
    # Create backup
    mkdir -p "$BACKUP_DIR"
    cp "$file" "$BACKUP_DIR/"
    
    # Create temporary file
    cp "$file" "$temp_file"
    
    # Replace IP addresses
    while IFS= read -r line; do
        if [[ $line =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\| ]]; then
            original_ip="${BASH_REMATCH[1]}"
            new_ip=$(create_ip_mapping "$original_ip")
            sed -i "s/\b$original_ip\b/$new_ip/g" "$temp_file"
        fi
    done < <(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$temp_file" | sort -u)
    
    # Replace DNS names
    while IFS= read -r line; do
        if [[ $line =~ ^([a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z]{2,})\| ]]; then
            original_dns="${BASH_REMATCH[1]}"
            new_dns=$(create_dns_mapping "$original_dns")
            sed -i "s/\b$original_dns\b/$new_dns/g" "$temp_file"
        fi
    done < <(grep -oE '\b([a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z]{2,})\b' "$temp_file" | sort -u)
    
    # Replace hostnames
    while IFS= read -r line; do
        if [[ $line =~ ^([a-zA-Z0-9][a-zA-Z0-9-]*)\| ]]; then
            original_host="${BASH_REMATCH[1]}"
            new_host=$(create_dns_mapping "$original_host")
            sed -i "s/\b$original_host\b/$new_host/g" "$temp_file"
        fi
    done < <(grep -oE '\b[a-zA-Z0-9][a-zA-Z0-9-]*\b' "$temp_file" | sort -u)
    
    # Move temporary file back
    mv "$temp_file" "$file"
}

# Main script
echo "Starting log anonymization..."

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Process all log files
find "$LOG_DIR" -type f -name "*.log" | while read -r file; do
    anonymize_file "$file"
done

# Save mapping files
echo "Saving IP and DNS mappings..."
cp "$IP_MAP_FILE" "$BACKUP_DIR/ip_mapping.txt"
cp "$DNS_MAP_FILE" "$BACKUP_DIR/dns_mapping.txt"

# Cleanup
rm -rf "$TEMP_DIR"

echo "Log anonymization completed. Backups saved in $BACKUP_DIR"
echo "IP and DNS mappings saved in $BACKUP_DIR/ip_mapping.txt and $BACKUP_DIR/dns_mapping.txt" 