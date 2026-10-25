#!/bin/zsh
# Generate Eymra.xcodeproj from project.yml. Run after adding or removing files.
source "${0:A:h}/common.sh"
[[ -f Config/Secrets.xcconfig ]] || cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
xcodegen generate --quiet
