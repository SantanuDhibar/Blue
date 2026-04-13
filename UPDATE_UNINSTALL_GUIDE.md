# Update and Uninstall Features

This document describes the new update and uninstall features added to the Blue VPN Script.

## Update Script

The update script allows you to update individual components or all scripts without performing a full reinstallation.

### Features

- **Update All Scripts**: Updates all VPN scripts, menu systems, and utilities in one go
- **Component-Specific Updates**: Update only specific components:
  - SSH/WS Scripts
  - XRAY Scripts (VMESS, VLESS, Trojan, Shadowsocks)
  - Menu Scripts
  - Bandwidth Management Scripts
  - System Utilities
- **Version Check**: Check current version against the latest available version
- **Progress Tracking**: Visual feedback for each script being updated

### Usage

#### From Menu
1. Run `menu` command
2. Select option `29` (UPDATE SCRIPT)
3. Choose your update mode:
   - Option 1: Update all scripts (recommended)
   - Option 2: Update specific component
   - Option 3: Check for updates

#### From Command Line
```bash
update
```

### Update Options

#### Update All Scripts
This is the recommended option that updates all components:
- Account creation scripts (SSH, VMESS, VLESS, Trojan, Shadowsocks)
- Menu scripts (all protocol menus)
- System utilities (restart, autoreboot, clearlog, etc.)
- Monitoring tools (cek-trafik, etc.)

#### Update Specific Components

**1. SSH/WS Scripts**
- Updates SSH account management scripts
- Updates SSH menu system

**2. XRAY Scripts**
- Updates VMESS, VLESS, Trojan, Shadowsocks account creation
- Updates protocol-specific menus

**3. Menu Scripts**
- Updates main menu system

**4. System Utilities**
- Updates restart/reboot scripts
- Updates logging and cleanup tools
- Updates backup/restore scripts

### Benefits

- **No Downtime**: Updates scripts without affecting running services
- **Selective Updates**: Update only what you need
- **Safe**: Doesn't modify user data or configurations
- **Fast**: Much quicker than full reinstallation
- **Convenient**: Can be run from the menu or command line

---

## Uninstall Script

The uninstall script completely removes the Blue VPN Script and all its components from your system.

### Features

- **Complete Removal**: Removes all installed scripts, services, and configurations
- **Safety Confirmation**: Requires typing "YES" to confirm uninstall
- **Automatic Backup**: Creates a final backup before removal
- **Service Cleanup**: Stops and disables all VPN services
- **Firewall Reset**: Cleans up custom firewall rules
- **Cron Job Removal**: Removes all automated tasks

### Usage

#### From Menu
1. Run `menu` command
2. Select option `30` (UNINSTALL SCRIPT)
3. Type `YES` (in capital letters) to confirm
4. Wait for uninstall to complete
5. Optionally reboot system

#### From Command Line
```bash
uninstall
```

### What Gets Removed

The uninstall process removes:

1. **Services** (stopped and disabled):
   - XRAY services (all variants)
   - SSH-WS services
   - Nginx (VPN configurations only)
   - Stunnel5
   - Dropbear
   - Bandwidth monitoring services
   - Host capture service

2. **Scripts** (removed from /usr/bin):
   - All account creation scripts
   - All menu scripts
   - All management utilities
   - Bandwidth monitoring tools
   - System utilities

3. **Configuration Files**:
   - /etc/xray directory
   - /etc/myvpn directory
   - /var/lib/scrz-prem directory
   - VPN-related nginx configs

4. **Systemd Service Files**:
   - All XRAY service files
   - Bandwidth monitoring services
   - Host capture service

5. **Cron Jobs**:
   - Automatic expiry checks
   - Backup tasks
   - Log cleanup tasks
   - Host capture tasks

6. **Firewall Rules**:
   - VPN-specific iptables rules

### What Gets Preserved

The following are preserved:

- **System Packages**: nginx, dropbear, stunnel5 (can be manually removed)
- **SSL Certificates**: /root/.acme.sh directory
- **Final Backup**: /root/blue-final-backup (user data backup)

### Final Backup

Before removal, the script creates a final backup at `/root/blue-final-backup/` containing:
- XRAY configurations
- User account data (passwd, shadow)
- VPN settings

This allows you to:
- Recover user data if needed
- Reinstall and restore later

To remove the backup:
```bash
rm -rf /root/blue-final-backup
```

### Optional Cleanup

After uninstall, you can optionally remove system packages:

```bash
# Remove packages
apt remove --purge nginx xray dropbear stunnel5

# Remove SSL certificates
rm -rf /root/.acme.sh

# Remove backup
rm -rf /root/blue-final-backup
```

### Important Notes

1. **Requires Confirmation**: You must type "YES" (in capitals) to confirm
2. **Creates Backup**: User data is backed up before removal
3. **Reboot Recommended**: System reboot is recommended after uninstall
4. **Irreversible**: Once uninstalled, you'll need to run setup.sh again to reinstall

---

## Quick Reference

### Commands

```bash
# Update all scripts
update

# Uninstall completely
uninstall

# Access from menu
menu
# Then select option 29 for update or 30 for uninstall
```

### Menu Options

- **Option 29**: Update Script
- **Option 30**: Uninstall Script

### Update Modes

1. Update All Scripts (Recommended)
2. Update Specific Component
3. Check for Updates

### Component Categories

1. SSH/WS Scripts
2. XRAY Scripts (VMESS, VLESS, Trojan, Shadowsocks)
3. Menu Scripts
4. Bandwidth Management Scripts
5. System Utilities

---

## Troubleshooting

### Update Issues

**Problem**: Update fails for some scripts
- **Solution**: Run update again or update specific components

**Problem**: Version check shows "Unknown"
- **Solution**: Check internet connection and GitHub access

### Uninstall Issues

**Problem**: Some services won't stop
- **Solution**: Manually stop services with `systemctl stop <service-name>`

**Problem**: Files remain after uninstall
- **Solution**: Manually remove with `rm -rf <directory>`

**Problem**: Can't access system after uninstall
- **Solution**: Restore from /root/blue-final-backup if needed

---

## Support

For issues or questions:
- Telegram: @LamonLind
- GitHub: https://github.com/SantanuDhibar/Blue

---

## Changelog

### Version 1.0 (2024)
- Initial release of update script
- Initial release of uninstall script
- Menu integration (options 29 and 30)
- Component-based update system
- Safe uninstall with backup
