#!/bin/bash
set -e

echo "=== AmneziaWG Easy - Bare Metal Installation Script ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for required binaries
if [ ! -d "$SCRIPT_DIR/binaries" ] || [ ! -f "$SCRIPT_DIR/binaries/awg" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  ERROR: AmneziaWG binaries not found!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "The 'binaries/' directory is missing or incomplete."
    echo ""
    echo "Required files:"
    echo "  - awg (CLI tool)"
    echo "  - awg-quick (setup script)"
    echo "  - amneziawg.ko (kernel module, optional)"
    echo ""
    echo "Then transfer this entire directory to your server."
    echo ""
    exit 1
fi

# Check for required source files
if [ ! -d "$SCRIPT_DIR/src" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  ERROR: Source files not found!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "The 'src/' directory is missing."
    echo ""
    echo "Please ensure you have the complete package with:"
    echo "  - src/"
    echo "  - binaries/"
    echo "  - install.sh"
    echo ""
    exit 1
fi

# Configuration variables
INSTALL_DIR="/opt/awg-easy"
CONFIG_DIR="/etc/amnezia/amneziawg"
WEB_USER="amnezia"
WEB_PORT="${WEB_PORT:-51821}"
WG_PORT="${WG_PORT:-51820}"
WG_HOST="${WG_HOST:-}"
PASSWORD="${PASSWORD:-}"

# v15 requires INIT_* variables for unattended setup (optional)
# If not provided, web UI will show setup wizard
# Group 1 requires: INIT_USERNAME, INIT_PASSWORD, INIT_HOST, INIT_PORT
INIT_ENABLED="${INIT_ENABLED:-false}"
INIT_USERNAME="${INIT_USERNAME:-admin}"
if [ -n "$WG_HOST" ] && [ -n "$PASSWORD" ]; then
    INIT_ENABLED="true"
    INIT_PASSWORD="$PASSWORD"
    INIT_HOST="$WG_HOST"
    INIT_PORT="$WG_PORT"
fi

echo "Installation Directory: $INSTALL_DIR"
echo "Config Directory: $CONFIG_DIR"
if [ "$INIT_ENABLED" = "true" ]; then
    echo "Setup Mode: Unattended (using WG_HOST and PASSWORD)"
    echo "WireGuard Host: $WG_HOST"
else
    echo "Setup Mode: Interactive (web UI setup wizard will appear)"
fi
echo "Web UI Port: $WEB_PORT"
echo "VPN Port: $WG_PORT"
echo ""

# Check and upgrade kernel if needed
echo "[1/10] Checking kernel compatibility..."
CURRENT_KERNEL=$(uname -r)
echo "Current kernel: $CURRENT_KERNEL"

if [[ "$CURRENT_KERNEL" == *"-virt"* ]]; then
    echo "⚠️  Detected -virt kernel. Upgrading to linux-lts for TUN/TAP support..."
    apk update
    apk add --no-cache linux-lts linux-lts-dev

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  REBOOT REQUIRED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "The linux-lts kernel has been installed."
    echo "Please reboot your server and run this script again."
    echo ""
    echo "To reboot now: reboot"
    echo "After reboot, run: WG_HOST=$WG_HOST PASSWORD=$PASSWORD $0"
    echo ""
    exit 0
fi

# Verify TUN module is available
echo "[2/10] Checking TUN/TAP support..."
if ! modprobe tun 2>/dev/null; then
    if ! lsmod | grep -q "^tun "; then
        echo "Error: TUN module not available"
        echo "This kernel does not support TUN/TAP which is required for WireGuard"
        echo "Please use linux-lts kernel or contact your VPS provider"
        exit 1
    fi
fi

if [ ! -c /dev/net/tun ]; then
    echo "Error: /dev/net/tun device not found"
    echo "TUN/TAP support is not available"
    exit 1
fi

echo "✓ TUN/TAP support confirmed"

# Install required Alpine packages
echo "[3/10] Installing system packages..."
apk update
apk add --no-cache nodejs npm iptables openrc bash

# Create directories
echo "[4/10] Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p /var/log/awg-easy

# Copy application files
echo "[5/10] Copying application files..."
cp -r "$SCRIPT_DIR/src"/* "$INSTALL_DIR/"

# Install AmneziaWG tools and kernel module
echo "[6/10] Installing AmneziaWG tools and kernel module..."

# Install AWG CLI tools
cp "$SCRIPT_DIR/binaries/awg" /usr/bin/
cp "$SCRIPT_DIR/binaries/awg-quick" /usr/bin/
chmod +x /usr/bin/awg /usr/bin/awg-quick
echo "✓ Installed: awg, awg-quick"

# Install kernel module if available
KERNEL_VERSION=$(uname -r)
MODULE_DIR="/lib/modules/$KERNEL_VERSION/kernel/net/wireguard"

if [ -f "$SCRIPT_DIR/binaries/amneziawg.ko" ]; then
    echo "Installing AmneziaWG kernel module for $KERNEL_VERSION..."
    mkdir -p "$MODULE_DIR"
    cp "$SCRIPT_DIR/binaries/amneziawg.ko" "$MODULE_DIR/"

    # Update module dependencies
    depmod -a

    # Try to load the module
    if modprobe amneziawg 2>/dev/null; then
        echo "✓ Installed and loaded: amneziawg.ko (kernel module)"
        echo "✓ AmneziaWG kernel module is active"
    else
        echo "⚠️  Kernel module installed but could not be loaded"
        echo "⚠️  This is normal if kernel version doesn't match (built for 6.12.50-0-lts)"
        echo "⚠️  System will use standard WireGuard instead"
    fi
else
    echo "⚠️  No kernel module found in binaries/"
    echo "⚠️  System will use standard WireGuard"
fi

# Install standard WireGuard tools for fallback
echo "Installing standard WireGuard tools..."
apk add --no-cache wireguard-tools
echo "✓ Installed standard WireGuard tools (wg, wg-quick)"

# Note: NO symlinks created - app auto-detects AWG kernel module and uses awg/wg accordingly

# AWG-Easy uses Nuxt/TypeScript - no path patching needed
echo "[7/10] Verifying application structure..."
if [ -f "$INSTALL_DIR/server/index.mjs" ]; then
    echo "✓ AWG-Easy Nuxt application detected"
else
    echo "⚠️  Warning: Expected Nuxt structure not found"
fi

# No npm install needed - already built in Docker image
echo "[8/10] Application is pre-built..."
echo "✓ Skipping dependency installation (already in build)"

# Create dedicated user (optional but recommended)
echo "[9/10] Creating service user..."
if ! id "$WEB_USER" &>/dev/null; then
    adduser -D -s /bin/sh "$WEB_USER"
fi

# Create environment file
echo "[10/10] Creating environment configuration..."
cat > /etc/awg-easy.env <<EOF
# AWG Easy v15 Configuration
# Initial setup variables (used on first run, if provided)
# Group 1: Required together for unattended setup
INIT_ENABLED=$INIT_ENABLED
${INIT_ENABLED:+INIT_USERNAME=$INIT_USERNAME}
${INIT_ENABLED:+INIT_PASSWORD=$INIT_PASSWORD}
${INIT_ENABLED:+INIT_HOST=$INIT_HOST}
${INIT_ENABLED:+INIT_PORT=$INIT_PORT}
# Group 2: Optional DNS defaults
${INIT_ENABLED:+INIT_DNS=1.1.1.1,1.0.0.1}
# Group 3: Optional CIDR defaults
${INIT_ENABLED:+INIT_IPV4_CIDR=10.8.0.0/24}
${INIT_ENABLED:+INIT_ALLOWED_IPS=0.0.0.0/0,::/0}

# Runtime configuration
PORT=$WEB_PORT
EXPERIMENTAL_AWG=true
INSECURE=true
DISABLE_IPV6=false
DEBUG=Server,WireGuard,Database

# AWG mode will be auto-detected:
# - If amneziawg kernel module is loaded: uses kernel mode
# - Otherwise: uses standard WireGuard
# Uncomment to force specific mode:
# OVERRIDE_AUTO_AWG=awg  # Force AWG mode (kernel if available)
# OVERRIDE_AUTO_AWG=wg   # Force standard WireGuard
EOF

chmod 600 /etc/awg-easy.env
echo "✓ Configuration saved to /etc/awg-easy.env"

# Enable IP forwarding
echo ""
echo "Configuring kernel parameters..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
if ! grep -q "net.ipv4.conf.all.src_valid_mark=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.conf.all.src_valid_mark=1" >> /etc/sysctl.conf
fi
sysctl -p >/dev/null 2>&1
echo "✓ IP forwarding enabled"

# Ensure TUN module loads on boot
echo ""
echo "Configuring TUN module to load on boot..."
if ! grep -q "^tun$" /etc/modules 2>/dev/null; then
    echo "tun" >> /etc/modules
fi
echo "✓ TUN module will load on boot"

# Create wrapper script to load environment variables
echo ""
echo "Creating service wrapper script..."
cat > /usr/local/bin/awg-easy-start <<'EOWRAPPER'
#!/bin/bash
set -a
[ -f /etc/awg-easy.env ] && . /etc/awg-easy.env
set +a

# Ensure /etc/wireguard exists for database
mkdir -p /etc/wireguard
chmod 755 /etc/wireguard

# Create symlink for awg-quick compatibility
mkdir -p /etc/amnezia/amneziawg
ln -sf /etc/wireguard/wg0.conf /etc/amnezia/amneziawg/wg0.conf 2>/dev/null || true

# Change to app directory so migrations can be found
cd /opt/awg-easy

exec /usr/bin/node /opt/awg-easy/server/index.mjs
EOWRAPPER

chmod +x /usr/local/bin/awg-easy-start
echo "✓ Service wrapper created"

# Create OpenRC service
echo "Creating OpenRC service..."
cat > /etc/init.d/awg-easy <<'EOSERVICE'
#!/sbin/openrc-run

name="AWG Easy"
description="AmneziaWG VPN Web UI (Nuxt)"

command="/usr/local/bin/awg-easy-start"
command_background=true
pidfile="/run/awg-easy.pid"

output_log="/var/log/awg-easy/output.log"
error_log="/var/log/awg-easy/error.log"

depend() {
    need net
    after firewall
}

start_pre() {
    # Ensure log directory exists
    mkdir -p /var/log/awg-easy

    # Load TUN module if not already loaded
    if ! lsmod | grep -q "^tun "; then
        modprobe tun 2>/dev/null || true
    fi
}

stop_post() {
    # Cleanup if needed
    rm -f "$pidfile"
}
EOSERVICE

chmod +x /etc/init.d/awg-easy
echo "✓ OpenRC service created"

# Enable and start service automatically
echo ""
echo "Enabling and starting service..."
rc-update add awg-easy default
rc-service awg-easy start

# Wait for service to start
sleep 5

# Check if service is running
if rc-service awg-easy status | grep -q "started"; then
    echo "✓ Service started successfully"
else
    echo "⚠️  Service failed to start. Check logs:"
    echo "    tail -50 /var/log/awg-easy/error.log"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [ "$INIT_ENABLED" = "true" ]; then
    echo "🌐 Web UI: http://$WG_HOST:$WEB_PORT"
    echo "🔑 Password: $PASSWORD"
    echo "🔒 VPN Port: udp://$WG_HOST:$WG_PORT"
else
    echo "🌐 Web UI: http://$(hostname -i):$WEB_PORT"
    echo "📋 Complete setup through web interface"
fi
echo ""
echo "📝 Configuration: /etc/awg-easy.env"
echo "📂 Install Directory: $INSTALL_DIR"
echo "📁 Config Directory: $CONFIG_DIR"
echo ""
echo "Service Management:"
echo "  rc-service awg-easy status"
echo "  rc-service awg-easy stop"
echo "  rc-service awg-easy restart"
echo ""
echo "View Logs:"
echo "  tail -f /var/log/awg-easy/output.log"
echo "  tail -f /var/log/awg-easy/error.log"
echo ""
echo "WireGuard Status:"
echo "  wg show wg0"
echo ""
