# Bandwidth Quota and Host Capture Fixes

## Issues Fixed

### 1. Host Capture Not Working
**Problem**: The host capture service name was inconsistent between setup and menu scripts.
- Setup created service: `host-capture`  
- Menu tried to use: `capture-host`

**Solution**:
- Fixed `menu-captured-hosts.sh` to reference the correct service name `host-capture`
- Service runs every 2 seconds capturing hosts from logs
- Menu now properly enables/disables the service

### 2. Bandwidth Quota Not Showing Usage
**Problem**: The quota system could set limits but didn't display current usage or percentage.

**Solution**:
- Enhanced `xray-quota-manager` with new features:
  - Added `usage` command to show detailed bandwidth info for a user
  - Enhanced `list` command to display usage, remaining, and percentage for all users
  - Fixed API query parsing to properly extract values from JSON response

### 3. Bandwidth Quota Not Enforcing Limits
**Problem**: Traffic monitor wasn't properly querying Xray stats API.

**Solution**:
- Fixed `xray-traffic-monitor` API response parsing
- Changed from `grep -oE 'value":[0-9]+'` to `grep -oE '"value":"[0-9]+"' | grep -oE '[0-9]+'`
- Added better logging to track quota enforcement
- Service runs every 60 seconds checking and enforcing quotas

### 4. No Easy Way to View Bandwidth Info
**Problem**: Users had to use command line to check bandwidth quotas and usage.

**Solution**:
- Created new `menu-bandwidth.sh` menu for easy quota management
- Added menu option 17 "BANDWIDTH QUOTAS" to main menu
- Menu shows:
  - All users with quotas, usage, remaining, and percentage
  - Color-coded status (green=ok, yellow=75%+, red=90%+ or over limit)
  - Monitor service status and logs
  - Options to set/remove quotas

### 5. Update Script Didn't Include New Components
**Problem**: Running update wouldn't fetch latest quota/host capture fixes.

**Solution**:
- Added `xray-quota-manager` and `xray-traffic-monitor` to update script
- Added `menu-bandwidth` to update script
- Added service restart after updating quota monitor
- Update script now properly maintains all bandwidth features

## New Commands Available

### View All Bandwidth Quotas
```bash
menu-bandwidth
# Or
xray-quota-manager list
```

### Check Specific User Bandwidth
```bash
xray-quota-manager usage user@example.com
```

### Set Bandwidth Quota
```bash
xray-quota-manager set user@example.com 10GB
```

### Remove Bandwidth Quota (Make Unlimited)
```bash
xray-quota-manager remove user@example.com
```

### Check Quota Monitor Status
```bash
systemctl status xray-quota-monitor
tail -f /var/log/xray-quota-monitor.log
```

### Host Capture Commands
```bash
# View captured hosts
menu-captured-hosts

# Manual scan
/usr/bin/capture-host

# Real-time monitor
/usr/bin/realtime-hosts

# Check service status
systemctl status host-capture
```

## How Bandwidth Quota Works Now

1. **During Account Creation**: 
   - Prompted to enter quota (e.g., 10GB, 500MB, 1TB)
   - Press Enter for unlimited
   - Quota is stored in `/etc/xray/client-quotas.conf`

2. **Monitoring**:
   - `xray-quota-monitor` service runs every 60 seconds
   - Queries Xray stats API for each user with a quota
   - Calculates: `total_usage = uplink + downlink`
   - Compares with quota limit

3. **Enforcement**:
   - When usage >= quota limit:
     - User is removed from `/etc/xray/config.json`
     - Xray service is restarted
     - User is marked as disabled in quota config
     - Event is logged

4. **Viewing Usage**:
   - Use menu option 17: "BANDWIDTH QUOTAS"
   - Use `xray-quota-manager list` command
   - Shows quota, usage, remaining, percentage, and status

## How Host Capture Works Now

1. **Automatic Capture**:
   - `host-capture` service runs every 2 seconds
   - Monitors logs: `/var/log/xray/access.log`, `/var/log/auth.log`, `/var/log/nginx/`
   - Extracts domains from various headers (Host, SNI, proxy-host, etc.)
   - Stores unique hosts in `/etc/myvpn/hosts.log`

2. **Viewing Hosts**:
   - Use menu option 27: "CAPTURED HOSTS"
   - Shows host, service type, source IP, and timestamp
   - Real-time monitor updates every 0.1 seconds

3. **Managing**:
   - Enable/disable auto-capture
   - Add hosts manually
   - Remove specific hosts
   - Clear all hosts

## File Structure

### Configuration Files
- `/etc/xray/client-quotas.conf` - Quota limits (format: email|bytes|enabled)
- `/etc/myvpn/hosts.log` - Captured hosts (format: host|service|ip|timestamp)

### Scripts
- `/usr/bin/xray-quota-manager` - CLI tool for quota management
- `/usr/bin/xray-traffic-monitor` - Background monitor service
- `/usr/bin/menu-bandwidth` - Interactive bandwidth menu
- `/usr/bin/capture-host` - Host capture script
- `/usr/bin/menu-captured-hosts` - Interactive host capture menu
- `/usr/bin/realtime-hosts` - Real-time host monitor display

### Services
- `host-capture.service` - Auto captures hosts every 2 seconds
- `xray-quota-monitor.service` - Enforces quotas every 60 seconds

### Logs
- `/var/log/xray-quota-monitor.log` - Quota enforcement events
- `/var/log/xray/access.log` - Xray traffic logs (used for host capture)

## Testing the Fixes

### Test Bandwidth Quota
1. Create a test user with a small quota:
   ```bash
   add-vless
   # Enter username, expiry, then quota: 1MB
   ```

2. Check quota was set:
   ```bash
   xray-quota-manager list
   ```

3. Generate some traffic, then check usage:
   ```bash
   xray-quota-manager usage testuser@example.com
   ```

4. Monitor will auto-disable when quota exceeded

### Test Host Capture
1. Check service is running:
   ```bash
   systemctl status host-capture
   ```

2. View captured hosts:
   ```bash
   menu-captured-hosts
   # Select option 1
   ```

3. Test manual scan:
   ```bash
   /usr/bin/capture-host
   ```

4. View real-time monitor:
   ```bash
   /usr/bin/realtime-hosts
   ```

## Updating Existing Installations

To get these fixes on an existing installation:

```bash
# Method 1: Use update menu
menu
# Select option 29 (Update Script)
# Select option 4 (Update System Utilities)

# Method 2: Use update command directly
update

# Method 3: Manual update of specific components
wget -O /usr/bin/xray-quota-manager "https://raw.githubusercontent.com/SantanuDhibar/Blue/main/xray-quota-manager"
wget -O /usr/bin/xray-traffic-monitor "https://raw.githubusercontent.com/SantanuDhibar/Blue/main/xray-traffic-monitor"
wget -O /usr/bin/menu-bandwidth "https://raw.githubusercontent.com/SantanuDhibar/Blue/main/menu-bandwidth.sh"
wget -O /usr/bin/menu-captured-hosts "https://raw.githubusercontent.com/SantanuDhibar/Blue/main/menu-captured-hosts.sh"
wget -O /usr/bin/menu "https://raw.githubusercontent.com/SantanuDhibar/Blue/main/menu4.sh"
chmod +x /usr/bin/xray-quota-manager /usr/bin/xray-traffic-monitor /usr/bin/menu-bandwidth /usr/bin/menu-captured-hosts /usr/bin/menu

# Restart services
systemctl daemon-reload
systemctl restart host-capture
systemctl restart xray-quota-monitor
```

## Troubleshooting

### Quota Not Enforcing
```bash
# Check monitor service
systemctl status xray-quota-monitor

# Check logs
tail -f /var/log/xray-quota-monitor.log

# Verify xray stats API is working
xray api stats --server=127.0.0.1:10085

# Restart monitor
systemctl restart xray-quota-monitor
```

### Host Capture Not Working
```bash
# Check service
systemctl status host-capture

# Test manual capture
/usr/bin/capture-host

# Check if logs exist
ls -la /var/log/xray/access.log
ls -la /etc/myvpn/hosts.log

# Restart service
systemctl restart host-capture
```

### Usage Not Showing
```bash
# Ensure xray is running
systemctl status xray

# Check if user exists in config
grep "user@example.com" /etc/xray/config.json

# Test API directly
xray api statsquery --server=127.0.0.1:10085 -pattern "user>>>user@example.com>>>traffic>>>uplink"
```

## Summary

All reported issues have been fixed:
- ✅ Host Capture working properly (service name fixed)
- ✅ Bandwidth quota showing usage (enhanced quota manager)
- ✅ Data usage visible per user (usage command added)
- ✅ Quota limit enforcement working (API parsing fixed)
- ✅ Update script includes all components (no need to reinstall)

Users can now easily view and manage bandwidth quotas through the new menu system, and host capture runs automatically with proper service management.
