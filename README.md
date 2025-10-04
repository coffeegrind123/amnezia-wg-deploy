# AmneziaWG Easy - Bare Metal Installer (Kernel Module Edition)

[![Build Status](https://github.com/coffeegrind123/amnezia-wg-deploy/actions/workflows/build-and-release.yml/badge.svg)](https://github.com/coffeegrind123/amnezia-wg-deploy/actions/workflows/build-and-release.yml)
[![Latest Release](https://img.shields.io/badge/release-latest-blue)](https://github.com/coffeegrind123/amnezia-wg-deploy/releases/latest)

One-command installer for [awg-easy](https://github.com/coffeegrind123/awg-easy) (master branch) on Alpine Linux. Includes conditional Amnezia theme switching and pre-built AmneziaWG kernel module support. No Docker required.

## Installation

```bash
wget https://github.com/coffeegrind123/amnezia-wg-deploy/releases/latest/download/awg-easy-deploy.tar.gz
tar -xzf awg-easy-deploy.tar.gz
cd awg-easy-deploy

# Unattended setup (recommended)
WG_HOST=vpn.example.com PASSWORD='your-password' ./install.sh

# Or interactive setup (web UI wizard)
./install.sh
```

**Requirements:** Alpine Linux with root access

**Ports:** 51820/udp (VPN), 51821/tcp (Web UI)

## What It Does

The installer:
1. Upgrades kernel from `-virt` to `linux-lts` (6.12.50) if needed (auto-reboot)
2. Installs Node.js, iptables, and system dependencies
3. Copies pre-built Nuxt app to `/opt/awg-easy`
4. Installs AmneziaWG tools (`awg`, `awg-quick`) and kernel module (`amneziawg.ko`)
5. Creates OpenRC service with auto-start
6. Configures IP forwarding and TUN module

**Note:** This version includes the AmneziaWG kernel module pre-compiled for Alpine LTS kernel 6.12.50. The module provides better performance and includes full UI support for all obfuscation parameters.

## Environment Variables

**Unattended setup** (all required):
- `WG_HOST` - Public hostname or IP
- `PASSWORD` - Web UI admin password
- `WG_PORT` - VPN port (default: 51820)
- `WEB_PORT` - Web UI port (default: 51821)

**Interactive setup:**
- Omit `WG_HOST` and `PASSWORD` to use web UI wizard

## Service Management

```bash
rc-service awg-easy status|start|stop|restart
tail -f /var/log/awg-easy/error.log
wg show wg0
```

## Configuration

**Files:**
- `/etc/awg-easy.env` - Service configuration
- `/etc/wireguard/wg0.conf` - WireGuard interface config (auto-generated)
- `/etc/amnezia/amneziawg/` - Config directory symlink

**Key settings in `/etc/awg-easy.env`:**
```bash
INIT_ENABLED=true              # Enables unattended setup
INIT_USERNAME=admin            # Web UI username
INIT_PASSWORD=xxx              # Web UI password
INIT_HOST=vpn.example.com      # VPN endpoint
INIT_PORT=51820                # VPN port
PORT=51821                     # Web UI port
EXPERIMENTAL_AWG=true          # Enable AmneziaWG features
OVERRIDE_AUTO_AWG=awg          # Force userspace mode
```

## Security

**Default config uses HTTP with basic auth.** For production:

1. Use strong passwords (20+ chars)
2. Add reverse proxy with HTTPS (nginx/caddy)
3. Restrict web UI access by IP:

```bash
iptables -A INPUT -p tcp --dport 51821 -s YOUR_ADMIN_IP -j ACCEPT
iptables -A INPUT -p tcp --dport 51821 -j DROP
```

## Troubleshooting

**Service won't start:**
```bash
tail -50 /var/log/awg-easy/error.log
lsmod | grep tun  # Verify TUN module loaded
uname -r          # Check kernel (must NOT be -virt)
```

**Kernel upgrade needed:**
```bash
apk add linux-lts
reboot
# Re-run installer after reboot
```

**Update to latest version:**
```bash
rc-service awg-easy stop
wget https://github.com/coffeegrind123/amnezia-wg-deploy/releases/latest/download/awg-easy-deploy.tar.gz
tar -xzf awg-easy-deploy.tar.gz
cd awg-easy-deploy
WG_HOST=vpn.example.com PASSWORD='password' ./install.sh
```

## How AmneziaWG Works

This version uses the **AmneziaWG kernel module** (`amneziawg.ko`) pre-compiled for Alpine LTS kernel 6.12.50:
- **Automatic detection**: Application detects `amneziawg` kernel module via `modinfo` and uses AWG tools (`awg`, `awg-quick`)
- **Fallback support**: If kernel module not available, uses standard WireGuard (`wg`, `wg-quick`)
- **Web UI**: Full support for configuring obfuscation parameters when AWG is active (Jc, Jmin, Jmax, S1-S4, H1-H4, I1-I5, J1-J3, Itime)
- **Better performance**: Kernel module provides 10-30% better CPU efficiency

**How detection works:**
1. On startup, app runs `modinfo amneziawg` to check if kernel module is loaded
2. If found: Uses AWG commands and shows obfuscation UI
3. If not found: Uses standard WireGuard commands, UI shows AWG is not active

## Credits

Based on [wg-easy](https://github.com/wg-easy/wg-easy) by Emile Nijssen
AmneziaWG fork: [imbtqd/awg-easy](https://github.com/imbtqd/awg-easy)
AmneziaWG core: [amnezia-vpn/amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go)

## License

GPL-3.0-only
