#!/bin/zsh
# Build, install, launch on the booted iPhone Duo sim, then screenshot both displays.
#   tool/run.sh [tag]        -> /tmp/<tag>-inner.png, /tmp/<tag>-outer.png (default tag: shot)
#   SHOT_DIR=... tool/run.sh  -> write screenshots elsewhere
#   NO_BUILD=1 tool/run.sh    -> skip the build, just relaunch + screenshot
# Display mapping (verified 2026-09-25 via `simctl io enumerate`):
#   --display=primary-1  (screen 3, 2853x2007)  = INNER (foldable) display
#   --display=primary    (screen 1, 2034x1398)  = OUTER display  <- also the default!
set -e
cd "$(dirname "$0")/.."
TAG=${1:-shot}
OUT=${SHOT_DIR:-/tmp}
SIM="iPhone Duo"
BUNDLE=com.duohack.duoassess
if [[ -z "$NO_BUILD" ]]; then
  LOG=build/xcodebuild.log; mkdir -p build
  set +e
  xcodebuild -project DuoAssess.xcodeproj -scheme DuoAssess \
    -destination "platform=iOS Simulator,name=$SIM" \
    -derivedDataPath build/DerivedData -quiet build >"$LOG" 2>&1
  BUILD_RC=$?
  set -e
  grep -E "error:|BUILD" "$LOG" || true
  [[ $BUILD_RC -eq 0 ]] || { echo "BUILD FAILED (rc=$BUILD_RC), see $LOG"; exit 1; }
fi
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/DuoAssess.app
[[ -d "$APP" ]] || { echo "no app bundle at $APP"; exit 1; }
xcrun simctl terminate "$SIM" $BUNDLE 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" $BUNDLE >/dev/null
sleep ${SETTLE:-6}
xcrun simctl io "$SIM" screenshot --display=primary-1 "$OUT/$TAG-inner.png" >/dev/null 2>&1
xcrun simctl io "$SIM" screenshot --display=primary   "$OUT/$TAG-outer.png" >/dev/null 2>&1
echo "inner: $OUT/$TAG-inner.png"; echo "outer: $OUT/$TAG-outer.png"
