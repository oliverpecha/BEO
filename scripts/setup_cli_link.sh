#!/bin/bash
# BEO CLI Symlink Installer
# Wires the beo_script_hub.sh to the global system path so the user can type 'beo'.

echo "🚀 Installing BEO Command Line Interface..."

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this installer with sudo or as root."
  exit 1
fi

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

echo "⚙️  Setting file permissions..."
chmod +x "$INSTALL_DIR"/*.sh
chmod +x "$INSTALL_DIR"/*.py

echo "🔗 Wiring up the 'beo' global command..."
ln -sf "$INSTALL_DIR/beo_script_hub.sh" /usr/local/bin/beo

if command -v beo >/dev/null 2>&1; then
    echo "✅ Success! You can now type 'beo' from anywhere to manage the proxy."
else
    echo "⚠️ Symlink created, but /usr/local/bin is not in your PATH."
fi
