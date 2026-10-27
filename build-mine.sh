#!/bin/bash
# Builds this fork and installs it to /Applications, replacing the official Sentient OS.
# Usage (from the repo folder): bash build-mine.sh
set -e
cd "$(dirname "$0")"

# 1. Signing team: your own free Apple ID team (gitignored, never committed).
if [ ! -f Signing.local.xcconfig ]; then
  TEAM=$(security find-certificate -a -c "Apple Development" -p ~/Library/Keychains/login.keychain-db 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
  if [ -z "$TEAM" ]; then
    echo "No Apple Development certificate yet. In Xcode: Settings > Accounts > your Apple ID > Manage Certificates > + > Apple Development. Then rerun."
    exit 1
  fi
  echo "DEVELOPMENT_TEAM = $TEAM" > Signing.local.xcconfig
  echo "Using team $TEAM"
fi

# 2. Build Release.
xcodebuild -project "Sentient OS macOS.xcodeproj" -scheme "Sentient OS macOS" -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -quiet build

APP=$(find build/Build/Products/Release -maxdepth 1 -name "*.app" | head -1)
[ -n "$APP" ] || { echo "Build finished but no .app found."; exit 1; }

# 3. Swap it in (settings and knowledge base are kept; they live outside the app).
osascript -e 'quit app "Sentient OS"' 2>/dev/null || true
sleep 2
DEST="/Applications/$(basename "$APP")"
[ -d "$DEST" ] && mv "$DEST" "$HOME/.Trash/$(basename "$APP" .app) (official $(date +%s)).app"
cp -R "$APP" /Applications/
open "$DEST"
echo "Installed your build: $DEST"
