#!/bin/zsh
# Install and launch the device build on the first connected iPhone.
source "${0:A:h}/common.sh"
DEVICE="$(device_udid)"
[[ -n "$DEVICE" ]] || { echo "No connected iPhone found (unlock it and tap Trust)"; exit 1; }
APP="$DERIVED/Build/Products/Debug-iphoneos/Eymra.app"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID"
