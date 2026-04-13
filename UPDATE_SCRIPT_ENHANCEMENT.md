# Update Script Enhancement - Self-Updating with Feature Management

## Overview

The enhanced `update.sh` script now intelligently manages features and updates itself automatically. When you download and run update.sh from the repository, it will:

1. **Self-update first** - Downloads latest version of itself before updating anything else
2. **Install new features** - Automatically adds new scripts and features
3. **Remove deprecated files** - Cleans up old/obsolete scripts
4. **Manage services** - Ensures all services are properly configured and running
5. **Create directories** - Sets up necessary directory structure

## How It Works

### Self-Update Process

```bash
# When you run update.sh, it:
1. Downloads latest update.sh from repository
2. Compares with current version
3. If different, replaces itself and restarts
4. Then proceeds with updating other components
```

**Example Flow:**
```bash
# User downloads and runs update.sh
wget -O /usr/bin/update "https://raw.githubusercontent.com/SantanuDhibar/Blue/main/update.sh"
chmod +x /usr/bin/update
update

# Script automatically:
# 1. Checks for update script updates
# 2. If newer version exists, downloads and replaces itself
# 3. Restarts with new version
# 4. Then shows menu to update components
```

### Feature Management

The script manages features in these ways:

#### 1. Installing New Features
- Downloads all latest scripts from repository
- Sets correct permissions automatically
- Ensures all necessary directories exist
- Configures and starts required services

#### 2. Removing Deprecated Features
- Maintains a list of deprecated/old files
- Automatically removes them during update
- Cleans up obsolete configurations

#### 3. Service Management
- Checks if services exist
- Enables auto-start on boot
- Starts stopped services
- Reloads systemd daemon when needed

#### 4. Directory Management
- Creates required directories if missing
- Sets proper permissions (755)
- Ensures data persistence locations exist

## Usage

### Method 1: Quick Update (Downloads latest update.sh)
```bash
# Download latest update.sh and run
wget -O /usr/bin/update "https://raw.githubusercontent.com/SantanuDhibar/Blue/main/update.sh"
chmod +x /usr/bin/update
update
```

### Method 2: Via Existing Installation
```bash
# If update command already exists
update

# Or via menu
menu → 29 (Update Script)
```

### Method 3: One-liner
```bash
# Download, make executable, and run in one command
wget -qO- https://raw.githubusercontent.com/SantanuDhibar/Blue/main/update.sh | bash
```

## Update Options

### Option 1: Update All Scripts (Recommended)
- Updates all components
- Installs new features
- Removes deprecated files
- Manages services
- Ensures directories exist
- Most comprehensive option

### Option 2: Update Specific Component
Choose from:
1. **SSH/WS Scripts** - SSH and WebSocket related
2. **XRAY Scripts** - VMESS, VLESS, Trojan, Shadowsocks
3. **Menu Scripts** - Main menu and sub-menus
4. **System Utilities** - Bandwidth, host capture, backup/restore, etc.

### Option 3: Check for Updates
- Shows current version
- Shows latest available version
- Prompts to update if newer version available

## What Gets Updated

### Core Scripts (Always Updated)
- All account creation scripts (add-ws, add-vless, add-tr, add-ssws, etc.)
- All menu scripts (menu-vless, menu-vmess, menu-bandwidth, etc.)
- System utilities (restart, backup, restore, xp, etc.)

### New Features (Automatically Installed)
- `menu-bandwidth` - Bandwidth quota management menu
- `xray-quota-manager` - CLI quota manager
- `xray-traffic-monitor` - Background quota enforcer
- `menu-captured-hosts` - Host capture management
- `capture-host` - Host capture script
- `realtime-hosts` - Real-time host monitor

### Services (Automatically Managed)
- `host-capture.service` - Auto-capture hosts every 2 seconds
- `xray-quota-monitor.service` - Enforce quotas every 60 seconds

### Directories (Automatically Created)
- `/etc/myvpn` - Main data directory
- `/etc/myvpn/usage` - Usage tracking data
- `/etc/myvpn/blocked_users` - Blocked user markers
- `/var/log` - Log directory

## Deprecated File Management

The script maintains a list of deprecated files that are automatically removed during update:

```bash
# In update.sh, deprecated files section:
local deprecated_files=(
    # Example: "/usr/bin/old-script"
    # Add any old/deprecated scripts here
)
```

**How to add deprecated files:**
1. Edit update.sh in repository
2. Add file path to `deprecated_files` array
3. Commit and push changes
4. Next update will remove those files automatically

## Service Management Details

### What the script does for services:

1. **Checks if service file exists**
   ```bash
   if [ -f /etc/systemd/system/host-capture.service ]; then
   ```

2. **Reloads systemd daemon**
   ```bash
   systemctl daemon-reload
   ```

3. **Enables auto-start on boot**
   ```bash
   systemctl enable host-capture
   ```

4. **Starts service if not running**
   ```bash
   if ! systemctl is-active --quiet host-capture; then
       systemctl start host-capture
   fi
   ```

### Services Managed:
- **host-capture** - Captures hosts from logs
- **xray-quota-monitor** - Enforces bandwidth quotas

## Update Flow Diagram

```
User runs: update
    ↓
Check for update.sh updates
    ↓
Download latest update.sh
    ↓
Compare with current version
    ↓
If different → Replace and restart
    ↓
Show menu
    ↓
User selects option
    ↓
Download components from repo
    ↓
Set permissions
    ↓
Remove deprecated files
    ↓
Ensure directories exist
    ↓
Manage services (enable/start)
    ↓
Show summary
    ↓
Done!
```

## Examples

### Example 1: Fresh Update
```bash
$ update
[INFO] Checking for update script updates...
[INFO] Update script has new version, updating...
[DONE] Update script updated! Restarting with new version...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
           Blue VPN Script - Update Tool
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Select update mode:

  [1] Update All Scripts (Recommended)
  [2] Update Specific Component
  [3] Check for Updates
  [0] Exit

Select option: 1
```

### Example 2: Updating All
```bash
[INFO] Updating all scripts...
Updating add-ws... ✓
Updating add-vless... ✓
Updating menu-bandwidth... ✓
Updating xray-quota-manager... ✓
...
[INFO] Checking for deprecated files...
[INFO] No deprecated files found
[INFO] Managing system services...
[INFO] Started host-capture service
[INFO] Started xray-quota-monitor service
[INFO] Services managed successfully

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Update Summary:
  Success: 45
  Failed: 0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[INFO] All necessary features installed and services configured!
```

### Example 3: Specific Component
```bash
Select component to update:

  [1] SSH/WS Scripts
  [2] XRAY Scripts (VMESS, VLESS, Trojan, Shadowsocks)
  [3] Menu Scripts
  [4] System Utilities
  [5] Update ALL Components
  [0] Back to Menu

Select option: 4
[INFO] Updating system utilities...
[DONE] System utilities updated!

[INFO] Managing system services...
[INFO] Services managed successfully
```

## Benefits

### For Users:
- ✅ **No manual file management** - Script handles everything
- ✅ **Always up-to-date** - Self-updates before updating others
- ✅ **Automatic cleanup** - Removes old/deprecated files
- ✅ **Service management** - Ensures all services running
- ✅ **No full reinstall needed** - Update in place

### For Developers:
- ✅ **Easy feature rollout** - Add to repo, users get automatically
- ✅ **Deprecation management** - Add to list, files auto-removed
- ✅ **Service deployment** - Update script handles service setup
- ✅ **Version control** - Script version tracked separately

## Troubleshooting

### Update script not updating itself
```bash
# Manually download latest
wget -O /usr/bin/update "https://raw.githubusercontent.com/SantanuDhibar/Blue/main/update.sh"
chmod +x /usr/bin/update
```

### Services not starting
```bash
# Check service files exist
ls -la /etc/systemd/system/host-capture.service
ls -la /etc/systemd/system/xray-quota-monitor.service

# Manually manage
systemctl daemon-reload
systemctl enable host-capture xray-quota-monitor
systemctl start host-capture xray-quota-monitor
systemctl status host-capture xray-quota-monitor
```

### Directories not created
```bash
# Manually create
mkdir -p /etc/myvpn/usage
mkdir -p /etc/myvpn/blocked_users
chmod -R 755 /etc/myvpn
```

### Download failures
```bash
# Check internet connection
ping -c 3 raw.githubusercontent.com

# Try with verbose output
wget -v -O /usr/bin/test "https://raw.githubusercontent.com/SantanuDhibar/Blue/main/menu4.sh"
```

## Technical Details

### Self-Update Mechanism
```bash
# Downloads to temporary location
wget -q -O /tmp/update.sh.new https://...

# Compares with current
cmp -s /tmp/update.sh.new /usr/bin/update

# If different, replaces and restarts
cp /tmp/update.sh.new /usr/bin/update
exec /usr/bin/update "$@"
```

### Permission Handling
```bash
# All scripts get execute permission
chmod +x /usr/bin/script-name

# Directories get 755
chmod 755 /etc/myvpn
```

### Error Handling
- Silent failures on service restarts (2>/dev/null)
- Continues even if some downloads fail
- Shows summary of successes/failures
- Cleans up temporary files

## Future Enhancements

Possible improvements:
- Backup before update
- Rollback capability
- Update changelog display
- Automatic scheduling (daily checks)
- Email notifications
- Update logs

## Summary

The enhanced update.sh script provides:
- ✅ Self-updating capability
- ✅ Automatic feature installation
- ✅ Deprecated file removal
- ✅ Service management
- ✅ Directory creation
- ✅ No manual intervention needed
- ✅ Safe and reliable updates

Users can now simply run `update` and the script handles everything automatically, ensuring all features are installed, old files are removed, and services are properly configured.
