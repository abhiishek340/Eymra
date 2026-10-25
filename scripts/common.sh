#!/bin/zsh
# Shared settings for every script. Source it; do not run it.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
PROJECT="Eymra.xcodeproj"
SCHEME="Eymra"
BUNDLE_ID="app.eymra.Eymra"
DERIVED="$ROOT/build/DerivedData"
SIM_NAME="${SIM_NAME:-iPhone 18 Pro}"
SIM_DEST="platform=iOS Simulator,name=$SIM_NAME"

# Keep build output small: errors, interesting warnings, test results, final status.
beautify() {
  if command -v xcbeautify >/dev/null 2>&1; then
    xcbeautify --quiet --disable-logging
  else
    grep -E "error:|warning: .*(deprecated|unused)|Test Case .* (passed|failed)|\*\* .* (SUCCEEDED|FAILED)" || true
  fi
}

sim_udid() {
  xcrun simctl list devices available -j | /usr/bin/python3 -I -c "
import json,sys
name=sys.argv[1]
for rt,devs in json.load(sys.stdin)['devices'].items():
  for d in devs:
    if d['name']==name: print(d['udid']); sys.exit()
" "$SIM_NAME"
}

# UDID of the first connected physical iPhone, empty if none.
device_udid() {
  xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /connected/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }'
}
