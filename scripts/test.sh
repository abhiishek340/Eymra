#!/bin/zsh
# Run tests on the Simulator. Optional args are passed through, e.g. -only-testing:EymraTests/SelectionTests
source "${0:A:h}/common.sh"
"$ROOT/scripts/gen.sh"
set -o pipefail
xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never "$@" 2>&1 | beautify
