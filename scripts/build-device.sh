#!/bin/zsh
# Build a signed Debug app for a connected iPhone. Needs DEVELOPMENT_TEAM in Config/Secrets.xcconfig.
source "${0:A:h}/common.sh"
"$ROOT/scripts/gen.sh"
grep -qE "^DEVELOPMENT_TEAM *= *[A-Z0-9]{10}" Config/Secrets.xcconfig || { echo "Set DEVELOPMENT_TEAM in Config/Secrets.xcconfig"; exit 1; }
set -o pipefail
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates 2>&1 | beautify
