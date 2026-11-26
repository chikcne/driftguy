#!/bin/bash
# Repack the current game, build, and install + launch it on the connected iPhone.
# Usage: ./deploy-ios.sh
set -euo pipefail

cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

BUNDLE_ID=com.justin.driftguy.iosproto
TEAM_ID=3W86J823GB  # free Personal Team; passed explicitly so a Godot re-export cannot reset it
DERIVED=build/ios-derived
APP="$DERIVED/Build/Products/Debug-iphoneos/DriftguyProto.app"

DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /connected|available/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')
if [ -z "$DEVICE" ]; then
  echo "No iPhone found. Plug it in and unlock it." >&2
  exit 1
fi

echo "==> Packing game"
godot --headless --path . --export-pack "iOS" DriftguyProto.pck 2>&1 | grep -E "ERROR|error" || true

echo "==> Building"
xcodebuild -project DriftguyProto.xcodeproj -scheme DriftguyProto -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath "$DERIVED" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" build \
  2>&1 | grep -E "error:|BUILD" || true
[ -d "$APP" ] || { echo "Build failed." >&2; exit 1; }

echo "==> Installing"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null

echo "==> Launching"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 \
  && echo "Done." \
  || echo "Installed, but could not auto-launch (phone locked or profile not trusted). Open DriftguyProto on the phone."
