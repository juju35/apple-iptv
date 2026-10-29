#!/usr/bin/env bash
# App Store screenshots (iPhone 6.9", iPad 13", Apple TV), iPhone Duo screenshots (cover screen, inner screen open
# flat, player half folded as a book and on a table) and the README's smaller copies, from the app's demo mode
# (made-up channels, films and series) on fresh simulators.
#
#   scripts/screenshots.sh
#   IPHONE="iPhone 17 Pro Max" IPAD="iPad Pro 13-inch (M4)" scripts/screenshots.sh   # other device types
#   ONLY="iphone tv" scripts/screenshots.sh                                         # some of them only
#
# Needs Xcode, XcodeGen and Python 3 with Pillow (pip install pillow). The iPhone Duo ones also need the iOS 27.1
# simulator runtime (xcodebuild -downloadPlatform iOS) and duoctl, which folds the simulator
# (github.com/skarol/duoctl); without them they are skipped. The Screenshots workflow runs it.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

# In CI, a failure names its command and the app's latest crash, as annotations.
on_error() {
  local status=$? line=$1 command=$2 report summary
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  echo "::error title=screenshots.sh::line $line exited with $status: $command"
  report=$(find "$HOME/Library/Logs/DiagnosticReports" -name 'IPTV*' -newer project.yml 2>/dev/null | tail -1)
  if [ -n "$report" ]; then
    summary=$(grep -E '"exception"|"type"|"signal"|"codes"|"symbol"|"termination"|"indicator"' "$report" | head -40)
    echo "::error title=IPTV crash::${summary//$'\n'/%0A}"
  fi
}
trap 'on_error $LINENO "$BASH_COMMAND"' ERR

IPHONE="${IPHONE:-iPhone 18 Pro Max}"
IPAD="${IPAD:-iPad Pro 13-inch (M5)}"
TV="${TV:-Apple TV 4K (3rd generation)}"
DELAY="${DELAY:-6}"
BUNDLE=me.jstephan.iptv
OUT=appstore/screenshots
DERIVED=build/screenshots

# APP / TV_APP=path/to/IPTV.app use those builds (the Screenshots workflow builds once).
build() {
  local scheme="$1" destination="$2"
  [ -d AppleIPTV.xcodeproj ] || xcodegen --quiet
  mkdir -p build
  if ! xcodebuild build -quiet -project AppleIPTV.xcodeproj -scheme "$scheme" -configuration Debug \
    -destination "$destination" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO \
    >"build/screenshots-$scheme.log" 2>&1; then
    cat "build/screenshots-$scheme.log"
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      errors=$(grep -E "error" "build/screenshots-$scheme.log" | head -20)
      echo "::error title=xcodebuild $scheme::${errors//$'\n'/%0A}"
    fi
    exit 1
  fi
}

ios_app() {
  if [ -z "${APP:-}" ]; then
    build IPTV 'generic/platform=iOS Simulator'
    APP="$DERIVED/Build/Products/Debug-iphonesimulator/IPTV.app"
  fi
  echo "$APP"
}

tv_app() {
  if [ -z "${TV_APP:-}" ]; then
    build IPTV-tvOS 'generic/platform=tvOS Simulator'
    TV_APP="$DERIVED/Build/Products/Debug-appletvsimulator/IPTV.app"
  fi
  echo "$TV_APP"
}

# prepare <udid> <folder> <app>: English system, 9:41 status bar (not on tvOS), the app installed.
prepare() {
  local udid="$1" dir="$2" app="$3"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$app"
  rm -rf "$dir"
  mkdir -p "$dir"
}

# launch <udid> <screen>: the app again, in demo mode on that screen. Right after a boot or a fold, the system may
# refuse to open apps for a moment (simctl exits with 149): tried again a few times.
launch() {
  local attempt udid="$1" screen="$2"
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  for attempt in 1 2 3 4 5; do
    if xcrun simctl launch "$udid" "$BUNDLE" -demo YES -demoScreen "$screen" \
      -AppleLanguages '(en)' -AppleLocale en_US >/dev/null; then
      return 0
    fi
    echo "Launch $attempt refused on $udid ($screen), trying again"
    sleep 5
  done
  return 1
}

# shoot <device type> <folder> <app> <screen>...
shoot() {
  local type="$1" dir="$OUT/$2" app="$3"
  shift 3
  local udid n=1 screen file
  udid=$(xcrun simctl create "IPTV screenshots" "$type")
  trap 'xcrun simctl delete "$udid" >/dev/null 2>&1 || true' RETURN
  prepare "$udid" "$dir" "$app"
  for screen in "$@"; do
    launch "$udid" "$screen"
    sleep $((n == 1 ? DELAY * 2 : DELAY))
    file=$(printf '%s/%02d-%s.png' "$dir" "$n" "$screen")
    xcrun simctl io "$udid" screenshot --type=png "$file" >/dev/null
    echo "$file"
    n=$((n + 1))
  done
}

# retry <command...>: duoctl sometimes fails to reach the simulator right after a fold; tried again a few times.
retry() {
  local attempt
  for attempt in 1 2 3; do
    if (trap - ERR; "$@"); then return 0; fi
    echo "$* failed ($attempt), trying again"
    sleep 5
  done
  "$@"
}

# iPhone Duo: closed (cover screen), open flat (inner screen), then the player half folded: held as a book
# (vertical fold, video beside the controls) and set on a table in portrait (horizontal fold, video above them).
shoot_duo() {
  local dir="$OUT/iphone-duo" runtime udid app
  runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
ids = [r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
ok = [i for i in ids if tuple(map(int, i.rsplit("iOS-", 1)[1].split("-")[:2])) >= (27, 1)]
print(ok[-1] if ok else "")')
  if [ -z "$runtime" ] || ! command -v duoctl >/dev/null; then
    echo "No iOS 27.1 runtime or no duoctl: no iPhone Duo screenshots"
    return 0
  fi
  app=$(ios_app)
  udid=$(xcrun simctl create "IPTV screenshots Duo" "iPhone Duo" "$runtime")
  trap 'xcrun simctl delete "$udid" >/dev/null 2>&1 || true' RETURN
  prepare "$udid" "$dir" "$app"
  export DUOCTL_UDID="$udid"

  retry duoctl close
  launch "$udid" home
  sleep $((DELAY * 2))
  duoctl screenshot "$dir/01-cover.png"
  retry duoctl open --duration 1
  sleep "$DELAY"
  duoctl screenshot "$dir/02-open.png"
  launch "$udid" player
  sleep "$DELAY"
  retry duoctl half --duration 1
  sleep "$DELAY"
  duoctl screenshot "$dir/03-player-book.png"
  retry duoctl rotate portrait
  retry duoctl hinge 110 --duration 1
  sleep "$DELAY"
  duoctl screenshot "$dir/04-player-tabletop.png"
  ls "$dir"/*.png
}

only="${ONLY:-iphone ipad duo tv}"
for part in ${only//,/ }; do
  case "$part" in
    build) ios_app >/dev/null; tv_app >/dev/null; exit 0 ;;
    iphone) shoot "$IPHONE" iphone-6.9 "$(ios_app)" home movies detail live settings ;;
    ipad) shoot "$IPAD" ipad-13 "$(ios_app)" home detail ;;
    duo) shoot_duo ;;
    tv) shoot "$TV" apple-tv "$(tv_app)" home movies detail live search ;;
    *) echo "Unknown ONLY part: $part" >&2; exit 2 ;;
  esac
done

python3 scripts/screenshots_post.py "$OUT" screenshots
