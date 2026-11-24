#!/usr/bin/env bash
# Runs the Android integration tests on a connected emulator/phone.
# `flutter test` reinstalls the app, which drops runtime permissions, so the microphone and
# notification grants are re-applied in the background as soon as the package appears.
# Usage (Git Bash, from app/):  tool/integration_android.sh [device-id] [extra flutter test args]
set -u
export MSYS_NO_PATHCONV=1
ADB="${ADB:-adb}"
command -v "$ADB" >/dev/null || ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
DEVICE="${1:-emulator-5554}"; shift || true
PKG=app.earmark.recorder
(
  while true; do
    "$ADB" -s "$DEVICE" shell pm grant $PKG android.permission.RECORD_AUDIO 2>/dev/null &&
      "$ADB" -s "$DEVICE" shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null
    sleep 1 # each pm call starts a process on the device; polling faster disturbs timing tests
  done
) &
GRANTER=$!
# A screen that sleeps mid-run draws no frames, and a live widget test then waits forever.
# Wake it once here; during the run the app keeps it on (debug test mode, see useTestTone).
"$ADB" -s "$DEVICE" shell input keyevent KEYCODE_WAKEUP
"$ADB" -s "$DEVICE" shell wm dismiss-keyguard
flutter test "${TARGET:-integration_test}" -d "$DEVICE" "$@"
STATUS=$?
kill $GRANTER 2>/dev/null
exit $STATUS
