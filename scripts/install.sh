#!/bin/bash
set -e

APP_NAME="AiShot.app"
INSTALL_DIR="/Applications"
TMP_DIR="$(mktemp -d)"
ZIP_URL="https://github.com/Icebitz/ai-screenshot/releases/latest/tag/0.1.0/AiShot.zip"

echo "🚀 Installing AiShot..."

# macOS only
if [[ "$(uname)" != "Darwin" ]]; then
  echo "❌ macOS only."
  exit 1
fi

# Check dependencies
for cmd in curl unzip; do
  if ! command -v $cmd >/dev/null; then
    echo "❌ Required command not found: $cmd"
    exit 1
  fi
done

echo "⬇️ Downloading AiShot..."
curl -L "$ZIP_URL" -o "$TMP_DIR/AiShot.zip"

echo "📦 Extracting..."
unzip -q "$TMP_DIR/AiShot.zip" -d "$TMP_DIR"

# Validate app
if [[ ! -d "$TMP_DIR/$APP_NAME" ]]; then
  echo "❌ AiShot.app not found in ZIP."
  exit 1
fi

# Remove old version
if [[ -d "$INSTALL_DIR/$APP_NAME" ]]; then
  echo "🗑 Removing existing installation..."
  sudo rm -rf "$INSTALL_DIR/$APP_NAME"
fi

# Install
echo "📁 Installing to /Applications..."
sudo cp -R "$TMP_DIR/$APP_NAME" "$INSTALL_DIR"

# Remove Gatekeeper quarantine (ZIP adds this!)
echo "🔓 Removing Gatekeeper quarantine..."
sudo xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME"

# Fix permissions
sudo chmod -R 755 "$INSTALL_DIR/$APP_NAME"

# Cleanup
rm -rf "$TMP_DIR"

echo "✅ AiShot installed successfully!"

# Launch app
open "$INSTALL_DIR/$APP_NAME"
