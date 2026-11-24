#!/usr/bin/env bash
# Before/after record for the "make it expensive" pass, on an EMULATOR: screenshots of the main
# screens and short screen recordings of the key motions, in the given system theme.
# Usage (Git Bash, from app/):  tool/capture_android.sh emulator-5554 <out-dir> light|dark
set -u
export MSYS_NO_PATHCONV=1
ADB="${ADB:-adb}"
command -v "$ADB" >/dev/null || ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
D="${1:?emulator id}"; OUTDIR="${2:?out dir}"; THEME="${3:?light|dark}"
PKG=app.earmark.recorder
a() { "$ADB" -s "$D" "$@"; }
[ "$(a shell getprop ro.kernel.qemu | tr -d '\r')" = 1 ] || { echo "refusing: $D is not an emulator"; exit 1; }
mkdir -p "$OUTDIR" build/ci-logs
[ "$THEME" = dark ] && a shell cmd uimode night yes >/dev/null || a shell cmd uimode night no >/dev/null
(while true; do a shell pm grant $PKG android.permission.RECORD_AUDIO 2>/dev/null && a shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null; sleep 1; done) &
GRANTER=$!
a shell input keyevent KEYCODE_WAKEUP
a shell run-as $PKG rm -f files/capture_scene.txt 2>/dev/null
flutter test integration_test/capture_test.dart -d "$D" > "build/ci-logs/capture-$THEME.txt" 2>&1 &
FT=$!
LAST=""
while kill -0 $FT 2>/dev/null; do
  SCENE=$(a shell run-as $PKG cat files/capture_scene.txt 2>/dev/null | tr -d '\r')
  if [ -n "$SCENE" ] && [ "$SCENE" != "$LAST" ]; then
    LAST="$SCENE"
    case "$SCENE" in
      done) ;;
      clip_*)
        a shell screenrecord --time-limit 4 --bit-rate 6000000 /sdcard/$SCENE.mp4 &
        echo "recording $SCENE" ;;
      *)
        sleep 0.8
        a exec-out screencap -p > "$OUTDIR/$THEME-$SCENE.png"
        echo "captured $SCENE" ;;
    esac
  fi
  sleep 0.3
done
sleep 5 # the last screen recording finishes
for f in $(a shell ls /sdcard/ | tr -d '\r' | grep '^clip_.*\.mp4$'); do
  a pull /sdcard/$f "$OUTDIR/$THEME-$f" >/dev/null && a shell rm /sdcard/$f
done
kill $GRANTER 2>/dev/null
a shell cmd uimode night no >/dev/null
grep -E "All tests|Some tests|\[E\]" "build/ci-logs/capture-$THEME.txt"
ls "$OUTDIR" | grep "^$THEME-" | tr '\n' ' '; echo
