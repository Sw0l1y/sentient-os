#!/bin/bash
# Installs the Discord -> Sentient reader and runs it nightly at 2:30 AM and at login.
# Usage: bash install.sh        Uninstall: bash install.sh --uninstall
set -e
DIR="$HOME/.sentient"
LABEL="com.nathan.discord-sentient"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
OUT="$HOME/Sentient Sources/Discord"

if [ "$1" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST" "$DIR/discord_cache_to_md.py"
  echo "Removed. Notes in '$OUT' and archive in $DIR were left in place."
  exit 0
fi

PY="$(command -v python3)"
[ -n "$PY" ] || { echo "python3 not found. Run: xcode-select --install"; exit 1; }

mkdir -p "$DIR" "$OUT" "$HOME/Library/LaunchAgents"
cp "$(dirname "$0")/discord_cache_to_md.py" "$DIR/"

# Discord compresses responses with brotli.
"$PY" -c "import brotli" 2>/dev/null || "$PY" -m pip install --user --quiet brotli \
  || "$PY" -m pip install --user --quiet --break-system-packages brotli

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$PY</string><string>$DIR/discord_cache_to_md.py</string>
  </array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>30</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$DIR/discord-sentient.log</string>
  <key>StandardErrorPath</key><string>$DIR/discord-sentient.log</string>
</dict></plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Running once now..."
"$PY" "$DIR/discord_cache_to_md.py"
echo
echo "Done. Last step: in Sentient Settings, add the folder:"
echo "  $OUT"
