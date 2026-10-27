#!/bin/bash
# Installs the nightly review of the official Sentient repo (2:15 AM, ahead of Sentient's 3 AM
# analysis; runs on next wake if asleep). Starts from what the fork already has, so only later
# upstream changes get reviewed.
# Usage: bash install.sh        Run now: bash install.sh --run        Uninstall: bash install.sh --uninstall
set -e
DIR="$HOME/.sentient"
REPO="$HOME/sentient-os"
LABEL="com.nathan.sentient-upstream-review"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "$1" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  rm -rf "$PLIST" "$DIR/sentient_upstream_review.sh" "$DIR/upstream-review"
  echo "Removed. 'Sentient upstream updates.md' was left in place."
  exit 0
fi

mkdir -p "$DIR" "$HOME/Library/LaunchAgents"
# Upstream is fetch-only: its push URL is deliberately not a URL.
git -C "$REPO" remote get-url upstream >/dev/null 2>&1 \
  || git -C "$REPO" remote add upstream https://github.com/Sentient-OS-Labs/sentient-os.git
git -C "$REPO" remote set-url --push upstream no-push-to-upstream
git -C "$REPO" fetch -q upstream
[ -f "$DIR/upstream-reviewed-sha" ] || git -C "$REPO" merge-base main upstream/main > "$DIR/upstream-reviewed-sha"
[ -f "$DIR/upstream-reviewed-release" ] || gh release list -R Sentient-OS-Labs/sentient-os --limit 20 \
  --json tagName,publishedAt --jq 'sort_by(.publishedAt) | reverse | .[0].tagName' > "$DIR/upstream-reviewed-release"

cp "$(dirname "$0")/review.sh" "$DIR/sentient_upstream_review.sh"
chmod +x "$DIR/sentient_upstream_review.sh"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$DIR/sentient_upstream_review.sh</string>
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>2</integer><key>Minute</key><integer>15</integer>
  </dict>
  <key>StandardOutPath</key><string>$DIR/upstream-review.log</string>
  <key>StandardErrorPath</key><string>$DIR/upstream-review.log</string>
</dict></plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed: checks nightly at 2:15 AM. Log: $DIR/upstream-review.log"
echo "Reviewed up to $(cut -c1-7 "$DIR/upstream-reviewed-sha"), release $(cat "$DIR/upstream-reviewed-release")."

if [ "$1" = "--run" ]; then
  launchctl kickstart "gui/$(id -u)/$LABEL"
  echo "Started a run now; watch the log."
fi
