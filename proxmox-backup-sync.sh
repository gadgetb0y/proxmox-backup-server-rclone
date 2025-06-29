#!/bin/bash

# Proxmox Backup Sync Script for Cron
# Syncs Proxmox backup archives via SFTP using rclone
# Author: John Federico (https://homeserverguides.com)
# Usage: Make executable and add to crontab for automated backups
# AI Disclosure: Parts of this script were created with the help of an LLM
#

#=============================================================================
# CONFIGURATION VARIABLES - MODIFY THESE FOR YOUR ENVIRONMENT
#=============================================================================

# Source directory containing backup files (PBS datastore structure)
SOURCE_DIR="/mnt/datastore/NAME_OF_YOUR_DATASTORE"

# SFTP connection details
SFTP_HOST="XXXXXXX.your-storagebox.de"
SFTP_USER="XXXXXXX"
SFTP_KEY="/home/rclone/.ssh/id_rsa" # Create a new user named rclone
SFTP_PORT="23"
REMOTE_DIR="/home/pbs" # subdirectory for PBS sync

# Logging configuration
LOG_DIR="/home/rclone/remote/pbs/logs" # log files in the user rclone directory
LOG_FILE="${LOG_DIR}/pbs-rclone-sync.log"
MAX_LOG_SIZE="10M"

# Retention settings (optional)
KEEP_LOCAL_DAYS="0"  # Set to 0 to disable local cleanup # 0 since PBS manages this
KEEP_REMOTE_DAYS="30"  # Set to 0 to disable remote cleanup

# Permission check settings (can take a long time depending on your setup)
SKIP_PERMISSION_CHECK="false"  # Set to "true" to always skip permission checks
AUTO_SKIP_PERMISSION_CHECK="true"  # Automatically skip if recent check was successful
PERMISSION_CHECK_INTERVAL_DAYS="7"  # How often to run permission checks (in days)

# Email notification via external SMTP (optional) Make sure you have curl or msmtp installed
NOTIFY_EMAIL="email@domain"  # Set email address to enable notifications
MAIL_SUBJECT="Proxmox Backup Sync"

# External SMTP configuration (leave empty to use local mail system)
SMTP_SERVER="smtp.my.domain"        # e.g., "smtp.gmail.com"
SMTP_PORT="587"       # Common ports: 587 (TLS), 465 (SSL), 25 (plain)
SMTP_USERNAME="email@my.domain"      # Your SMTP username/email
SMTP_PASSWORD="cHaNgEmEtOsOmEtHiNgSeCuRe"      # Your SMTP password or app-specific password
SMTP_FROM="another_email@domain"          # From email address (can be same as SMTP_USERNAME)
SMTP_ENCRYPTION="tls" # Options: tls, ssl, none

#=============================================================================
# SCRIPT FUNCTIONS
#=============================================================================

# Function to write timestamped log entries
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Function to send email notification
send_notification() {
    local status="$1"
    local message="$2"
    
    if [[ -n "$NOTIFY_EMAIL" ]]; then
        if [[ -n "$SMTP_SERVER" ]]; then
            # Use external SMTP server
            send_smtp_email "$status" "$message"
        else
            # Use local mail system
            echo "$message" | mail -s "$MAIL_SUBJECT - $status" "$NOTIFY_EMAIL" 2>/dev/null
        fi
    fi
}

# Function to send email via external SMTP
send_smtp_email() {
    local status="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create temporary files for email content
    local email_body=$(mktemp)
    local email_headers=$(mktemp)
    
    # Clean up temp files on exit
    trap "rm -f $email_body $email_headers" RETURN
    
    # Prepare email content
    cat > "$email_body" << EOF
Subject: $MAIL_SUBJECT - $status
From: $SMTP_FROM
To: $NOTIFY_EMAIL
Date: $(date -R)

Proxmox Backup Sync Report
==========================

Status: $status
Timestamp: $timestamp
Host: $(hostname -f)
Source: $SOURCE_DIR
Destination: $SFTP_HOST:$REMOTE_DIR

Details:
$message

---
This is an automated message from the Proxmox backup sync script.
EOF

    # Send email using different methods based on available tools
    if command -v curl &> /dev/null; then
        send_email_curl "$email_body"
    elif command -v sendemail &> /dev/null; then
        send_email_sendemail "$status" "$message"
    elif command -v msmtp &> /dev/null; then
        send_email_msmtp "$email_body"
    else
        log_message "WARNING: No suitable SMTP client found. Install curl, sendemail, or msmtp for external SMTP support."
        # Fallback to local mail if available
        if command -v mail &> /dev/null; then
            echo "$message" | mail -s "$MAIL_SUBJECT - $status" "$NOTIFY_EMAIL" 2>/dev/null
        fi
    fi
}

# Function to send email using curl
send_email_curl() {
    local email_file="$1"
    local smtp_url
    
    case "$SMTP_ENCRYPTION" in
        "ssl")
            smtp_url="smtps://$SMTP_SERVER:$SMTP_PORT"
            ;;
        "tls")
            smtp_url="smtp://$SMTP_SERVER:$SMTP_PORT"
            ;;
        "none")
            smtp_url="smtp://$SMTP_SERVER:$SMTP_PORT"
            ;;
        *)
            smtp_url="smtp://$SMTP_SERVER:$SMTP_PORT"
            ;;
    esac
    
    local curl_opts=()
    
    if [[ "$SMTP_ENCRYPTION" == "tls" ]]; then
        curl_opts+=("--ssl-reqd")
    fi
    
    curl --silent --show-error \
        --url "$smtp_url" \
        --user "$SMTP_USERNAME:$SMTP_PASSWORD" \
        --mail-from "$SMTP_FROM" \
        --mail-rcpt "$NOTIFY_EMAIL" \
        --upload-file "$email_file" \
        "${curl_opts[@]}" \
        2>/dev/null || log_message "WARNING: Failed to send email notification via curl"
}

# Function to send email using sendemail
send_email_sendemail() {
    local status="$1"
    local message="$2"
    
    local sendemail_opts=(
        -f "$SMTP_FROM"
        -t "$NOTIFY_EMAIL"
        -u "$MAIL_SUBJECT - $status"
        -s "$SMTP_SERVER:$SMTP_PORT"
        -xu "$SMTP_USERNAME"
        -xp "$SMTP_PASSWORD"
        -m "$message"
        -q
    )
    
    case "$SMTP_ENCRYPTION" in
        "tls")
            sendemail_opts+=(-o tls=yes)
            ;;
        "ssl")
            sendemail_opts+=(-o tls=yes)
            ;;
    esac
    
    sendemail "${sendemail_opts[@]}" 2>/dev/null || \
        log_message "WARNING: Failed to send email notification via sendemail"
}

# Function to send email using msmtp
send_email_msmtp() {
    local email_file="$1"
    
    # Create temporary msmtp config
    local msmtp_config=$(mktemp)
    trap "rm -f $msmtp_config" RETURN
    
    cat > "$msmtp_config" << EOF
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile ~/.msmtp.log

account default
host $SMTP_SERVER
port $SMTP_PORT
from $SMTP_FROM
user $SMTP_USERNAME
password $SMTP_PASSWORD
EOF

    if [[ "$SMTP_ENCRYPTION" == "ssl" ]]; then
        echo "tls_starttls off" >> "$msmtp_config"
    elif [[ "$SMTP_ENCRYPTION" == "none" ]]; then
        echo "tls off" >> "$msmtp_config"
        echo "auth off" >> "$msmtp_config"
    fi
    
    msmtp --file="$msmtp_config" --read-envelope-from < "$email_file" 2>/dev/null || \
        log_message "WARNING: Failed to send email notification via msmtp"
}

# Function to rotate log file if it gets too large
rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local current_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)
        local max_size_bytes=$(echo "$MAX_LOG_SIZE" | sed 's/M/000000/g' | sed 's/K/000/g')
        
        if [[ $current_size -gt $max_size_bytes ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
            log_message "Log file rotated due to size limit"
        fi
    fi
}

# Function to clean up old local files
cleanup_local_files() {
    if [[ $KEEP_LOCAL_DAYS -gt 0 ]]; then
        log_message "Cleaning up local files older than $KEEP_LOCAL_DAYS days"
        find "$SOURCE_DIR" -type f \( -name "*.tar.gz" -o -name "*.tar.lzo" -o -name "*.vma.lzo" -o -name "*.pxar" -o -name "*.img" -o -name "*.fidx" -o -name "*.didx" -o -name "*.blob" \) | \
        while read -r file; do
            if [[ $(find "$file" -mtime +$KEEP_LOCAL_DAYS -print 2>/dev/null) ]]; then
                rm -f "$file" && log_message "Deleted old local file: $(basename "$file")"
            fi
        done
    fi
}

# Function to check if permission check is needed
needs_permission_check() {
    local permission_check_file="/home/rclone/.last_permission_check"
    
    # Always check if manually requested
    if [[ "$SKIP_PERMISSION_CHECK" == "true" ]]; then
        return 1  # Don't check
    fi
    
    # If auto-skip is disabled, always check
    if [[ "$AUTO_SKIP_PERMISSION_CHECK" != "true" ]]; then
        return 0  # Check needed
    fi
    
    # Check if permission check file exists and is recent
    if [[ -f "$permission_check_file" ]]; then
        local last_check=$(stat -c %Y "$permission_check_file" 2>/dev/null || echo 0)
        local current_time=$(date +%s)
        local days_since_check=$(( (current_time - last_check) / 86400 ))
        
        if [[ $days_since_check -lt $PERMISSION_CHECK_INTERVAL_DAYS ]]; then
            log_message "Skipping permission check (last check was $days_since_check days ago)"
            return 1  # Don't check
        fi
    fi
    
    return 0  # Check needed
}

# Function to ensure proper permissions on backup files
ensure_permissions() {
    if ! needs_permission_check; then
        return 0
    fi
    
    log_message "Checking and fixing permissions for backup files..."
    local permission_check_file="/home/rclone/.last_permission_check"
    
    # Find files that don't have group read permission and fix them
    local files_fixed=0
    while IFS= read -r -d '' file; do
        if [[ ! -r "$file" ]]; then
            chmod g+r "$file" 2>/dev/null && ((files_fixed++))
        fi
    done < <(find "$SOURCE_DIR" -type f \( -name "*.tar.gz" -o -name "*.tar.lzo" -o -name "*.vma.lzo" -o -name "*.pxar" -o -name "*.img" -o -name "*.fidx" -o -name "*.didx" -o -name "*.blob" -o -name "owner" \) ! -perm -g+r -print0 2>/dev/null)
    
    # Find directories that don't have group execute permission and fix them
    local dirs_fixed=0
    while IFS= read -r -d '' dir; do
        if [[ ! -x "$dir" ]]; then
            chmod g+x "$dir" 2>/dev/null && ((dirs_fixed++))
        fi
    done < <(find "$SOURCE_DIR" -type d ! -perm -g+x -print0 2>/dev/null)
    
    log_message "Permission check completed: $files_fixed files and $dirs_fixed directories fixed"
    
    # Update the timestamp file
    touch "$permission_check_file"
}
cleanup_remote_files() {
    if [[ $KEEP_REMOTE_DAYS -gt 0 ]]; then
        log_message "Cleaning up remote files older than $KEEP_REMOTE_DAYS days"
        rclone delete "sftp-backup:$REMOTE_DIR" \
            --min-age "${KEEP_REMOTE_DAYS}d" \
            --include "*.tar.gz" \
            --include "*.tar.lzo" \
            --include "*.vma.lzo" \
            --dry-run 2>/dev/null || true
    fi
}

#=============================================================================
# MAIN SCRIPT EXECUTION
#=============================================================================

# Set up error handling
set -euo pipefail
trap 'log_message "ERROR: Script failed on line $LINENO"' ERR

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Rotate log file if needed
rotate_log

# Start logging
log_message "=== Starting Proxmox backup sync ==="
log_message "Source: $SOURCE_DIR"
log_message "Destination: $SFTP_HOST:$REMOTE_DIR"

# Check if source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    log_message "ERROR: Source directory does not exist: $SOURCE_DIR"
    send_notification "FAILED" "Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

# Check if SSH key exists and has correct permissions
if [[ ! -f "$SFTP_KEY" ]]; then
    log_message "ERROR: SSH key file not found: $SFTP_KEY"
    send_notification "FAILED" "SSH key file not found: $SFTP_KEY"
    exit 1
fi

# Set correct permissions on SSH key if needed
chmod 600 "$SFTP_KEY"

# Check if rclone is installed
if ! command -v rclone &> /dev/null; then
    log_message "ERROR: rclone is not installed or not in PATH"
    send_notification "FAILED" "rclone is not installed or not in PATH"
    exit 1
fi

# Configure rclone remote if it doesn't exist
if ! rclone listremotes | grep -q "sftp-backup:"; then
    log_message "Configuring rclone SFTP remote..."
    rclone config create sftp-backup sftp \
        host="$SFTP_HOST" \
        user="$SFTP_USER" \
        key_file="$SFTP_KEY" \
        port="$SFTP_PORT" \
        2>/dev/null || {
        log_message "ERROR: Failed to configure rclone remote"
        send_notification "FAILED" "Failed to configure rclone remote"
        exit 1
    }
fi

# Test connectivity
log_message "Testing SFTP connectivity..."
if ! rclone lsd "sftp-backup:/home/" &>/dev/null; then
    log_message "ERROR: Cannot connect to SFTP server"
    send_notification "FAILED" "Cannot connect to SFTP server: $SFTP_HOST"
    exit 1
fi

# Ensure proper permissions before sync
ensure_permissions

# Count files to be synced (including subdirectories)
file_count=$(find "$SOURCE_DIR" -type f \( -name "*.tar.gz" -o -name "*.tar.lzo" -o -name "*.vma.lzo" -o -name "*.pxar" -o -name "*.img" -o -name "*.fidx" -o -name "*.didx" -o -name "*.blob" \) | wc -l)
log_message "Found $file_count backup files to sync"

if [[ $file_count -eq 0 ]]; then
    log_message "No backup files found to sync"
    send_notification "INFO" "No backup files found to sync from $SOURCE_DIR"
    exit 0
fi

# Perform the sync
log_message "Starting rclone sync operation..."
sync_start_time=$(date +%s)

rclone sync "$SOURCE_DIR/" "sftp-backup:$REMOTE_DIR/" \
    --filter "+ *.tar.gz" \
    --filter "+ *.tar.lzo" \
    --filter "+ *.vma.lzo" \
    --filter "+ *.pxar" \
    --filter "+ *.img" \
    --filter "+ *.fidx" \
    --filter "+ *.didx" \
    --filter "+ *.blob" \
    --filter "+ owner" \
    --filter "- *.tmp" \
    --filter "- *.lock" \
    --filter "- *.partial" \
    --filter "- *.temp" \
    --filter "- *" \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    --stats 30s \
    --stats-one-line \
    2>&1 | while IFS= read -r line; do
        echo "[$timestamp] RCLONE: $line" >> "$LOG_FILE"
    done

sync_end_time=$(date +%s)
sync_duration=$((sync_end_time - sync_start_time))

# Check if sync was successful
if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    log_message "Sync completed successfully in ${sync_duration} seconds"
    
    # Perform cleanup if enabled
    cleanup_local_files
    cleanup_remote_files
    
    # Send success notification
    send_notification "SUCCESS" "Backup sync completed successfully. $file_count files synced in ${sync_duration} seconds."
    
else
    log_message "ERROR: Sync operation failed"
    send_notification "FAILED" "Backup sync operation failed. Check logs at $LOG_FILE"
    exit 1
fi

log_message "=== Backup sync completed ==="

# Exit successfully
exit 0
