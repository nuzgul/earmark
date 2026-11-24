#!/usr/bin/env bash
# Frame timing in a PROFILE build on an EMULATOR, through the real UI and the real engine
# (the emulator's virtual microphone, which hears silence unless host audio input is switched on).
# The app logs "FRAMES ..." every 10 s when built with EARMARK_FRAME_LOG (see lib/main.dart).
# Usage (Git Bash, from app/):  tool/frames_android.sh emulator-5554
set -u
export MSYS_NO_PATHCONV=1
ADB="${ADB:-adb}"
command -v "$ADB" >/dev/null || ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
D="${1:?emulator id}"
PKG=app.earmark.recorder
OUT=build/ci-logs
mkdir -p "$OUT"
a() { "$ADB" -s "$D" "$@"; }
[ "$(a shell getprop ro.kernel.qemu | tr -d '\r')" = 1 ] || { echo "refusing: $D is not an emulator"; exit 1; }

# Taps the control whose accessibility label is $1 (Flutter semantics show up as content-desc).
tap() {
  a shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  local xy
  xy=$(a shell cat /sdcard/ui.xml | python -c "
import re, sys
x = sys.stdin.read()
m = re.search(r'content-desc=\"' + re.escape(sys.argv[1]) + r'\"[^>]*?bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', x)
print('' if not m else f'{(int(m[1]) + int(m[3])) // 2} {(int(m[2]) + int(m[4])) // 2}')
" "$1")
  [ -z "$xy" ] && { echo "no control labelled '$1'"; return 1; }
  a shell input tap $xy
}

echo "== building the profile app with the frame log"
flutter build apk --profile --dart-define=EARMARK_FRAME_LOG=true > "$OUT/frames-build.txt" 2>&1 || { echo "FAIL: build"; tail -5 "$OUT/frames-build.txt"; exit 1; }
a uninstall $PKG >/dev/null 2>&1
a install build/app/outputs/flutter-apk/app-profile.apk >/dev/null || { echo "FAIL: install"; exit 1; }
a shell pm grant $PKG android.permission.RECORD_AUDIO
a shell pm grant $PKG android.permission.POST_NOTIFICATIONS
a shell input keyevent KEYCODE_WAKEUP
a logcat -c
a shell am start -W -n $PKG/.MainActivity >/dev/null
sleep 5
tap "Start recording" || exit 1
sleep 4
for i in 1 2 3 4 5 6; do
  tap "Bookmark this moment"
  sleep 2
done
sleep 12 # two more 10 s log ticks while recording
tap "Stop and save"
sleep 4
echo "== frame log (profile build, recording)"
a logcat -d -s flutter | grep FRAMES | sed 's/^.*FRAMES/RESULT FRAMES/'
a shell am force-stop $PKG
a uninstall $PKG >/dev/null && echo "profile app removed"
