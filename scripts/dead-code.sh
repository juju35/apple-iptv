#!/usr/bin/env bash
# Unused declarations and imports: SwiftLint's analyzer rules (unused_declaration, unused_import) over a clean
# simulator build of the iOS app. Used by the pre-push hook and the Build workflow.
#
#   scripts/dead-code.sh [compiler log]   # builds first when no log is given
#   REPORTER=github-actions-logging scripts/dead-code.sh build.log
set -euo pipefail
cd "$(dirname "$0")/.."

log="${1:-}"
if [ -z "$log" ]; then
  log="$(mktemp -t iptv-build).log"
  [ -d AppleIPTV.xcodeproj ] || xcodegen --quiet
  # Analyzer rules need every file compiled in this log: a clean build in its own DerivedData.
  derived="$(mktemp -d -t iptv-derived)"
  xcodebuild clean build -project AppleIPTV.xcodeproj -scheme IPTV \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO > "$log" || { tail -40 "$log"; exit 1; }
fi

swiftlint analyze --strict --quiet --compiler-log-path "$log" --reporter "${REPORTER:-xcode}" Sources
