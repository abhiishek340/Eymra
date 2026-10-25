#!/bin/zsh
# Build the app for the iOS Simulator.
source "${0:A:h}/common.sh"
"$ROOT/scripts/gen.sh"
set -o pipefail
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO 2>&1 | beautify
