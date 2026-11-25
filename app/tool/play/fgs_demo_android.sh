#!/usr/bin/env bash
# Demo video for Play's foreground-service declaration (FOREGROUND_SERVICE_MICROPHONE), on an EMULATOR:
# start recording, leave the app, mark and pause from the notification, come back, stop and save.
# Usage (Git Bash, from app/):  tool/play/fgs_demo_android.sh emulator-5554 ../dist/Earmark-foreground-service-demo.mp4
set -u
export MSYS_NO_PATHCONV=1
ADB="${ADB:-adb}"
command -v "$ADB" >/dev/null || ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
D="${1:?emulator id}"; OUT="${2:?out.mp4}"
PKG=app.earmark.recorder
a() { "$ADB" -s "$D" "$@"; }
[ "$(a shell getprop ro.kernel.qemu | tr -d '\r')" = 1 ] || { echo "refusing: $D is not an emulator"; exit 1; }

# Taps the first node whose content-desc or text matches the regex $1, waiting up to 15 s for it.
tap() {
  for _ in $(seq 15); do tap_once "$1" 2>/dev/null && return 0; sleep 1; done
  echo "nothing matches '$1'"; return 1
}
tap_once() {
  a shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  local xy
  xy=$(a shell cat /sdcard/ui.xml | python -c "
import re, sys
x = sys.stdin.read()
for node in re.findall(r'<node [^>]*>', x):
    labels = re.findall(r'(?:text|content-desc)=\"([^\"]*)\"', node)
    if any(re.search(sys.argv[1], l) for l in labels):
        b = list(map(int, re.findall(r'\d+', re.search(r'bounds=\"([^\"]*)\"', node)[1])))
        print((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
        break
" "$1")
  [ -z "$xy" ] && return 1
  a shell input tap $xy
}

a install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null || { echo "FAIL: install"; exit 1; }
a shell pm grant $PKG android.permission.RECORD_AUDIO
a shell pm grant $PKG android.permission.POST_NOTIFICATIONS
a shell input keyevent KEYCODE_WAKEUP
a shell am force-stop $PKG
a shell cmd uimode night no >/dev/null
a shell rm -f /sdcard/fgs.mp4
a shell screenrecord --time-limit 75 --bit-rate 4000000 /sdcard/fgs.mp4 &
REC=$!
sleep 2
a shell am start -W -n $PKG/.MainActivity >/dev/null
sleep 5
tap '^Start recording$' || exit 1; sleep 4
tap '^Bookmark this moment$'; sleep 3
a shell input keyevent KEYCODE_HOME; sleep 4                 # the app leaves the screen; recording goes on
a shell cmd statusbar expand-notifications; sleep 4          # the recording notification
# The notification's timer keeps the shade busy, so uiautomator cannot read it: its three action
# icons (Mark, Pause/Resume, Stop) are tapped where they sit on this 1080x2400 emulator.
a shell input tap 208 888; sleep 3                           # Mark from the notification
a shell input tap 332 888; sleep 3                           # Pause
a shell input tap 332 888; sleep 3                           # Resume
a shell cmd statusbar collapse; sleep 2
a shell am start -W -n $PKG/.MainActivity >/dev/null; sleep 4   # back in the app: the marks are there
tap '^Stop and save$' || a shell input tap 952 1160; sleep 5
kill $REC 2>/dev/null; sleep 3
WOUT=$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")
a pull /sdcard/fgs.mp4 "$WOUT" >/dev/null && a shell rm /sdcard/fgs.mp4 && echo "saved $OUT"
