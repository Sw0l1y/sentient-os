#!/bin/bash
# Installs the weekly refresh of ~/Sentient Sources/Claude (Sundays at 2 AM, ahead of Sentient's 3 AM
# analysis; runs on next wake if asleep).
# Usage: bash install.sh        Run now: bash install.sh --run        Uninstall: bash install.sh --uninstall
set -e
DIR="$HOME/.sentient"
LABEL="com.nathan.sentient-claude-notes"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "$1" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST" "$DIR/refresh_claude_notes.sh"
  echo "Removed. Notes in '$HOME/Sentient Sources/Claude' were left in place."
  exit 0
fi

mkdir -p "$DIR" "$HOME/Library/LaunchAgents"
cp "$(dirname "$0")/refresh.sh" "$DIR/refresh_claude_notes.sh"
chmod +x "$DIR/refresh_claude_notes.sh"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$DIR/refresh_claude_notes.sh</string>
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Weekday</key><integer>0</integer><key>Hour</key><integer>2</integer><key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key><string>$DIR/claude-notes.log</string>
  <key>StandardErrorPath</key><string>$DIR/claude-notes.log</string>
</dict></plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed: runs Sundays at 2 AM. Log: $DIR/claude-notes.log"

if [ "$1" = "--run" ]; then
  launchctl kickstart "gui/$(id -u)/$LABEL"
  echo "Started a run now; watch the log."
fi
