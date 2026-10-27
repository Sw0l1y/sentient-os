#!/bin/bash
# Installs the Discord -> Sentient reader and runs it nightly at 2:30 AM and at login.
# Usage: bash install.sh        Uninstall: bash install.sh --uninstall
set -e
DIR="$HOME/.sentient"
LABEL="com.nathan.discord-sentient"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
OUT="$HOME/Sentient Sources/Discord"
APP="$DIR/Sentient Discord Reader.app"

if [ "$1" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST" "$DIR/discord_cache_to_md.py"
  rm -rf "$APP"
  echo "Removed. Notes in '$OUT' and archive in $DIR were left in place."
  exit 0
fi

PY="$(command -v python3)"
[ -n "$PY" ] || { echo "python3 not found. Run: xcode-select --install"; exit 1; }

mkdir -p "$DIR" "$OUT" "$HOME/Library/LaunchAgents"
cp "$(dirname "$0")/discord_cache_to_md.py" "$DIR/"

# The launcher app holds Full Disk Access for the job (see reader_launcher.c).
# Signed with your Apple Development cert so the grant survives rebuilds; ad-hoc otherwise.
mkdir -p "$APP/Contents/MacOS"
clang -O2 -o "$APP/Contents/MacOS/discord-reader" "$(dirname "$0")/reader_launcher.c"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>Sentient Discord Reader</string>
  <key>CFBundleExecutable</key><string>discord-reader</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSBackgroundOnly</key><true/>
</dict></plist>
EOF
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*) \([0-9A-F]\{40\}\) "Apple Development.*/\1/p' | head -1)
codesign --force --sign "${IDENTITY:--}" "$APP"

# Discord compresses responses with brotli.
"$PY" -c "import brotli" 2>/dev/null || "$PY" -m pip install --user --quiet brotli \
  || "$PY" -m pip install --user --quiet --break-system-packages brotli

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$APP/Contents/MacOS/discord-reader</string>
  </array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>30</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$DIR/discord-sentient.log</string>
  <key>StandardErrorPath</key><string>$DIR/discord-sentient.log</string>
</dict></plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

sleep 3  # RunAtLoad just ran it once
echo "First run:"
cat "$DIR/discord-sentient.log"
echo
echo "Done. If it says permission denied: System Settings > Privacy & Security > Full Disk Access,"
echo "click +, press Cmd-Shift-G, paste the path below, and switch it on:"
echo "  $APP"
echo "Then add this folder in Sentient Settings > Knowledge Sources:"
echo "  $OUT"
