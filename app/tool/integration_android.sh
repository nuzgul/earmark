#!/usr/bin/env bash
# Runs the Android integration tests on a connected emulator/phone.
# `flutter test` reinstalls the app, which drops runtime permissions, so the microphone and
# notification grants are re-applied in the background as soon as the package appears.
# Each test file runs on its own with a time limit (one `flutter test` call for several files
# can hang on a device); on a hang the device log and a screenshot go to build/ci-logs/.
# Usage (Git Bash, from app/):  tool/integration_android.sh [device-id] [extra flutter test args]
#   TARGET=integration_test/clip_test.dart tool/integration_android.sh emulator-5554   (one file)
set -u
export MSYS_NO_PATHCONV=1
ADB="${ADB:-adb}"
command -v "$ADB" >/dev/null || ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
DEVICE="${1:-emulator-5554}"; shift || true
PKG=app.earmark.recorder
LIMIT="${LIMIT:-480}"
LOGS=build/ci-logs
mkdir -p "$LOGS"
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

run() { # file [extra flutter test args]
  local file=$1 name pid
  shift
  name=$(basename "$file" .dart)
  "$ADB" -s "$DEVICE" logcat -c 2>/dev/null
  flutter test "$file" -d "$DEVICE" "$@" &
  pid=$!
  for ((s = 0; s < LIMIT; s += 5)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      return $?
    fi
    sleep 5
  done
  echo "TIMEOUT: $file still running after ${LIMIT}s"
  "$ADB" -s "$DEVICE" exec-out screencap -p > "$LOGS/hang-$name.png" 2>/dev/null
  "$ADB" -s "$DEVICE" logcat -d -t 3000 > "$LOGS/logcat-$name.txt" 2>/dev/null
  kill "$pid" 2>/dev/null
  sleep 3
  kill -9 "$pid" 2>/dev/null
  return 124
}

STATUS=0
if [ -n "${TARGET:-}" ]; then
  run "$TARGET" "$@" || STATUS=1
else
  for f in integration_test/clip_test.dart integration_test/owner_sequence_test.dart; do
    run "$f" "$@" || STATUS=1
  done
fi
kill $GRANTER 2>/dev/null
exit $STATUS
