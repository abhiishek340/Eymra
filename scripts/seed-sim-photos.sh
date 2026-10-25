#!/bin/zsh
# Add the fixture JPEGs (with EXIF dates and GPS) to the Simulator's photo library
# and grant photo access, so the real PhotoKit + Vision path can be exercised.
source "${0:A:h}/common.sh"
UDID="$(sim_udid)"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl addmedia "$UDID" Fixtures/*.jpg
xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID" || true
echo "Seeded $(ls Fixtures/*.jpg | wc -l | tr -d ' ') photos into $SIM_NAME"
