#!/bin/zsh
# Records the demo tour on a fresh "Eymra Demo" Simulator seeded with a folder of trip photos.
# Usage: scripts/record-demo.sh <folder of JPEGs with EXIF dates> <output.mp4>
source "${0:A:h}/common.sh"
PHOTOS="${1:?folder of trip photos}"
OUT="${2:?output video}"
DEMO_NAME="Eymra Demo"
SIM_NAME="$DEMO_NAME"
SIM_DEST="platform=iOS Simulator,name=$SIM_NAME"

# A clean phone every time: no old photos, no saved account.
UDID="$(sim_udid)"
if [[ -n "$UDID" ]]; then
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  xcrun simctl delete "$UDID"
fi
DEVICE_TYPE="$(xcrun simctl list devicetypes -j | /usr/bin/python3 -I -c "import json,sys; print(next(d['identifier'] for d in json.load(sys.stdin)['devicetypes'] if d['name']=='iPhone 18 Pro'))")"
UDID="$(xcrun simctl create "$DEMO_NAME" "$DEVICE_TYPE")"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularMode active --cellularBars 4
xcrun simctl addmedia "$UDID" "$PHOTOS"/*.jpg

# Build once, install, grant photo access up front, then record only the tour.
xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO | beautify
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/Eymra.app"
xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID"

xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT" &
RECORDER=$!
sleep 2
TEST_RUNNER_EYMRA_DEMO=1 xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -only-testing:EymraUITests/DemoTour | beautify || true
sleep 1
kill -INT $RECORDER
wait $RECORDER 2>/dev/null || true
echo "Recorded $OUT"
