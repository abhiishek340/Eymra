#!/bin/zsh
# Build, install and launch on the Simulator. Pass extra launch args, e.g. -uiTesting
source "${0:A:h}/common.sh"
"$ROOT/scripts/build-sim.sh"
UDID="$(sim_udid)"
xcrun simctl boot "$UDID" 2>/dev/null || true
# Show the device window: Simulator.app up to Xcode 26, DeviceHub.app in Xcode 27.
for viewer in "$(xcode-select -p)/Applications/Simulator.app" "$(xcode-select -p)/../Applications/DeviceHub.app"; do
  [[ -d "$viewer" ]] && { open "$viewer" || true; break; }
done
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Eymra.app"
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
