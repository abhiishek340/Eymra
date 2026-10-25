#!/bin/zsh
# Usage: scripts/sdk-grep.sh <Framework> <Symbol>. Searches the iOS SDK headers and Swift interfaces.
set -euo pipefail
FW="$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/$1.framework"
grep -rn "$2" "$FW/Headers" "$FW/Modules" 2>/dev/null | head -40
