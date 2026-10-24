#!/bin/bash
# Build, sign and install Pocket03 on a connected iPhone.
#
# One-time setup: sign in to your Apple ID under Xcode -> Settings -> Accounts, and enable
# Developer Mode on the phone (Settings -> Privacy & Security -> Developer Mode).
#
# Usage: tools/install-device.sh [configuration]   # Debug (default) or Release
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
LOG=/tmp/pocket03-device.log

echo "==> Looking for a connected device"
DEVICE_JSON="$(mktemp)"
trap 'rm -f "$DEVICE_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1

# xcodebuild addresses the phone by its hardware UDID; devicectl by its CoreDevice identifier.
DEVICE_INFO="$(python3 - "$DEVICE_JSON" <<'PYEOF'
import json, sys
# Only real hardware: simulators also report as paired, and picking one silently builds for
# the wrong platform. Prefer a device with a live tunnel.
cands = []
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    conn = d.get("connectionProperties", {})
    hw = d.get("hardwareProperties", {})
    if hw.get("reality") != "physical":
        continue
    if hw.get("platform") != "iOS":
        continue
    if conn.get("pairingState") != "paired":
        continue
    # A paired but unplugged phone still appears here; xcodebuild cannot target it, so skip it
    # and say so rather than failing later with an opaque destination error.
    if conn.get("tunnelState") != "connected":
        continue
    cands.append((0, hw.get("udid", ""), d.get("identifier", ""), hw.get("marketingName", "iPhone")))
cands.sort()
if cands:
    _, udid, ident, name = cands[0]
    print(udid, ident, name)
PYEOF
)"

UDID="$(printf '%s' "$DEVICE_INFO" | cut -d' ' -f1)"
DEVICE_ID="$(printf '%s' "$DEVICE_INFO" | cut -d' ' -f2)"
DEVICE_NAME="$(printf '%s' "$DEVICE_INFO" | cut -d' ' -f3-)"

if [ -z "$UDID" ]; then
    echo "No connected iPhone." >&2
    echo "The phone may be paired but not attached. Plug it in over USB (or join the same" >&2
    echo "Wi-Fi network), unlock it, and run this again." >&2
    xcrun devicectl list devices 2>/dev/null | grep -i physical >&2 || true
    exit 1
fi
echo "    $DEVICE_NAME ($UDID)"

echo "==> Building and signing ($CONFIG)"
if ! xcodebuild -project Pocket03.xcodeproj -scheme Pocket03 \
        -configuration "$CONFIG" -destination "platform=iOS,id=$UDID" \
        -derivedDataPath build-device -allowProvisioningUpdates build > "$LOG" 2>&1; then
    echo "Build failed. Errors:" >&2
    grep -E "error:" "$LOG" | sort -u | head -5 >&2
    if grep -q "No Account for Team" "$LOG"; then
        echo >&2
        echo "Xcode has no Apple ID signed in. Open Xcode -> Settings -> Accounts -> +," >&2
        echo "add your Apple ID, then run this script again." >&2
    fi
    echo "Full log: $LOG" >&2
    exit 1
fi

APP="$(find "build-device/Build/Products/$CONFIG-iphoneos" -maxdepth 1 -name 'Pocket03.app' | head -1)"
[ -n "$APP" ] || { echo "Built app not found under build-device/." >&2; exit 1; }

echo "==> Installing $APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo
echo "Installed. On a first install with a free Apple ID, trust the developer on the phone:"
echo "Settings -> General -> VPN & Device Management -> Developer App."
echo "A free Apple ID signature expires after seven days; rerun this script to reinstall."
