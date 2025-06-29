# Proxmox Backup Server: rclone Sync Script

A comprehensive bash script for syncing Proxmox Backup Server (PBS) datastores to remote storage via rclone and SFTP. This script provides automated, reliable, and configurable off-site backup capabilities for your PBS infrastructure.

## Features

- **Complete PBS Datastore Sync** - Syncs entire PBS datastore including chunks, indexes, and metadata
- **Automated Scheduling** - Designed for unattended operation using cron
- **Smart Permission Management** - Automatic permission checking with configurable intervals
- **Email Notifications** - SMTP support for success/failure notifications
- **Comprehensive Logging** - Detailed logs with rotation and timestamping
- **File Retention** - Configurable local and remote file cleanup
- **Error Handling** - Robust error detection and recovery
- **Progress Monitoring** - Real-time sync statistics and progress reporting

## Prerequisites

### Software Requirements
- **rclone** - For file synchronization
- **Proxmox Backup Server** - Source datastore
- **SSH access** - To remote storage (SFTP)
- **Linux system** - Tested on Debian/Ubuntu
- **A user named** `rclone`


### Installation

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Or via package manager
apt update && apt install rclone

# Optional: For email notifications
apt install curl  # or sendemail, msmtp
```

## Quick Start

### 1. Clone and Setup

```bash
# Clone the repository
git clone https://git.gadgetboy.org/Homelab/proxmox-backup-server-rclone.git
cd proxmox-backup-server-rclone

# Make executable
chmod +x proxmox-backup-sync.sh

# Create dedicated user (recommended)
sudo useradd -m -s /bin/bash rclone
sudo usermod -a -G backup rclone  # Add to backup group for PBS access
```

### 2. Configure SSH Keys

```bash
# Generate SSH key pair
sudo -u rclone ssh-keygen -t rsa -b 4096 -f /home/rclone/.ssh/id_rsa

# Copy public key to remote server
sudo -u rclone ssh-copy-id -i /home/rclone/.ssh/id_rsa.pub -p 23 user@remote-server
```

### 3. Configure rclone Remote

```bash
# Configure SFTP remote
sudo -u rclone rclone config create sftp-backup sftp \
    host=your-server.com \
    user=your-username \
    port=23 \
    key_file=/home/rclone/.ssh/id_rsa
```

### 4. Configure Script
Edit the configuration variables at the top of the script:

```bash
# CONFIGURATION VARIABLES - MODIFY THESE FOR YOUR ENVIRONMENT

# Source directory containing PBS datastore
SOURCE_DIR="/mnt/datastore/datastore-name"

# SFTP connection details
SFTP_HOST="your-server.com"
SFTP_USER="your-username"
SFTP_KEY="/home/rclone/.ssh/id_rsa"
SFTP_PORT="23"
REMOTE_DIR="/home/pbs"

# Email notifications (optional)
NOTIFY_EMAIL="admin@example.com"
SMTP_SERVER="smtp.example.com"
SMTP_USERNAME="sender@example.com"
SMTP_PASSWORD="app-password"
```

### 5. Test the Script

```bash
# Run initial test
sudo -u rclone ./proxmox-backup-sync.sh

# Check logs
tail -f /home/rclone/logs/pbs-rclone-sync/backup-sync.log
```

### 6. Schedule with Cron
```bash
# Edit rclone user's crontab
sudo -u rclone crontab -e

# Add daily backup at 11 PM
0 23 * * * /home/rclone/remote/pbs/proxmox-backup-sync.sh >/dev/null 2>&1
```

## Configuration Options

### Core Settings
| Variable | Description | Default |
|----------|-------------|---------|
| `SOURCE_DIR` | PBS datastore path | `/mnt/datastore/datastore-name` |
| `SFTP_HOST` | Remote server hostname | - |
| `SFTP_USER` | SFTP username | - |
| `SFTP_KEY` | SSH private key path | `/home/rclone/.ssh/id_rsa` |
| `REMOTE_DIR` | Remote destination directory | `/home/pbs` |

### Performance Settings
| Variable | Description | Default |
|----------|-------------|---------|
| `SKIP_PERMISSION_CHECK` | Always skip permission checks | `false` |
| `AUTO_SKIP_PERMISSION_CHECK` | Auto-skip if recent check done | `true` |
| `PERMISSION_CHECK_INTERVAL_DAYS` | Days between permission checks | `7` |

### Retention Settings
| Variable | Description | Default |
|----------|-------------|---------|
| `KEEP_LOCAL_DAYS` | Local file retention (0=disabled) | `0` |
| `KEEP_REMOTE_DAYS` | Remote file retention (0=disabled) | `30` |

### Email Settings
| Variable | Description | Example |
|----------|-------------|---------|
| `NOTIFY_EMAIL` | Recipient email address | `admin@example.com` |
| `SMTP_SERVER` | SMTP server hostname | `smtp.gmail.com` |
| `SMTP_PORT` | SMTP port | `587` |
| `SMTP_USERNAME` | SMTP authentication username | `user@gmail.com` |
| `SMTP_PASSWORD` | SMTP password/app password | `app-password` |
| `SMTP_FROM` | From email address | `backup@example.com` |
| `SMTP_ENCRYPTION` | Encryption type (tls/ssl/none) | `tls` |

## Usage Examples

### Basic Usage

```bash
# Manual sync
./proxmox-backup-sync.sh

# Test run without changes
rclone sync /mnt/datastore/datastore-name/ sftp-backup:/home/pbs/ --dry-run
```

### Cron Schedule Examples

```bash
# Daily at 2:30 AM
30 2 * * * /path/to/proxmox-backup-sync.sh >/dev/null 2>&1

# Every 6 hours
0 */6 * * * /path/to/proxmox-backup-sync.sh >/dev/null 2>&1

# Weekly on Sunday at 3 AM
0 3 * * 0 /path/to/proxmox-backup-sync.sh >/dev/null 2>&1
```

### Log Monitoring
```bash
# Real-time log monitoring
tail -f /home/rclone/logs/pbs-rclone-sync/backup-sync.log

# Check for errors
grep ERROR /home/rclone/logs/pbs-rclone-sync/backup-sync.log

# View recent sync summary
tail -20 /home/rclone/logs/pbs-rclone-sync/backup-sync.log
```

## Troubleshooting

### Common Issues

**Permission Denied Errors**

```bash
# Check PBS datastore permissions
ls -la /mnt/datastore/datastore-name/

# Add rclone user to backup group
sudo usermod -a -G backup rclone

# Test file access
sudo -u rclone ls /mnt/datastore/datastore-name/
```

**SFTP Connection Issues**

```bash
# Test SSH connection manually
ssh -i /home/rclone/.ssh/id_rsa -p 23 user@remote-server

# Test rclone connection
rclone lsd sftp-backup:/

# Debug rclone connection
rclone lsd sftp-backup:/ --log-level DEBUG
```

**Large Sync Times**

```bash
# Enable bandwidth limiting
# Add to rclone command: --bwlimit 10M

# Skip permission checks for faster syncs
SKIP_PERMISSION_CHECK="true"
```

### Log Analysis

```bash
# Check sync statistics
grep "Transferred:" /home/rclone/logs/pbs-rclone-sync/backup-sync.log

# Find failed transfers
grep "ERROR" /home/rclone/logs/pbs-rclone-sync/backup-sync.log

# Monitor sync progress
grep "ETA" /home/rclone/logs/pbs-rclone-sync/backup-sync.log
```

## Security Considerations

### File Permissions

```bash
# Secure the script
chmod 750 /path/to/proxmox-backup-sync.sh
chown rclone:rclone /path/to/proxmox-backup-sync.sh

# Secure SSH keys
chmod 600 /home/rclone/.ssh/id_rsa
chmod 700 /home/rclone/.ssh/
```

### Best Practices
- Use dedicated `rclone` user with minimal privileges
- Store SMTP passwords in separate config file
- Regularly rotate SSH keys
- Monitor sync logs for suspicious activity
- Test restore procedures regularly

## Performance Optimization

### For Large Datastores (>1TB)

```bash
# Consider adding bandwidth limits
--bwlimit 50M

# Use multiple transfers (experimental)
--transfers 4

# Enable compression for slow links
--sftp-compress
```

### Permission Check Optimization

```bash
# Skip permission checks if not needed
SKIP_PERMISSION_CHECK="true"

# Or increase interval for stable environments
PERMISSION_CHECK_INTERVAL_DAYS="30"
```

## Compatible Storage Providers

This script works with any SFTP-compatible storage provider:
- **Hetzner Storage Box**
- **rsync.net**
- **Amazon S3** (via rclone SFTP gateway)
- **Google Cloud Storage** (via rclone SFTP gateway)
- **Backblaze B2** (via rclone SFTP gateway)
- **Custom SSH/SFTP servers**

## Contributing

1. Fork the repository on [git.gadgetboy.org](https://git.gadgetboy.org/Homelab/proxmox-backup-server-rclone)
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [Gitea Issues](https://git.gadgetboy.org/Homelab/proxmox-backup-server-rclone/issues)
- **Wiki**: [Project Wiki](https://git.gadgetboy.org/Homelab/proxmox-backup-server-rclone/wiki)
- **Repository**: [git.gadgetboy.org](https://git.gadgetboy.org/Homelab/proxmox-backup-server-rclone)

## Changelog

### v1.0.0
- Initial release
- Complete PBS datastore sync support
- Email notifications
- Automatic permission management
- Comprehensive logging and error handling

---

**⚠️ Important**: Always test backup and restore procedures before relying on this script for production data protection.
