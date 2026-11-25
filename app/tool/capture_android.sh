#!/usr/bin/env bash
# Before/after record for the "make it expensive" pass, on an EMULATOR: screenshots of the main
# screens and short screen recordings of the key motions, in the given system theme.
# Usage (Git Bash, from app/):  tool/capture_android.sh emulator-5554 <out-dir> light|dark
# Store screenshots: TEST=integration_test/store_tour_test.dart tool/capture_android.sh emulator-5554 build/store/raw light
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
(while true; do a shell pm grant $PKG android.permission.RECORD_AUDIO >/dev/null 2>&1 && a shell pm grant $PKG android.permission.POST_NOTIFICATIONS >/dev/null 2>&1; sleep 1; done) &
GRANTER=$!
a shell input keyevent KEYCODE_WAKEUP
a shell run-as $PKG rm -f files/capture_scene.txt files/capture_ack.txt 2>/dev/null
flutter test "${TEST:-integration_test/capture_test.dart}" -d "$D" > "build/ci-logs/capture-$THEME.txt" 2>&1 &
FT=$!
LAST=""
ack() { a shell "run-as $PKG sh -c 'echo $1 > files/capture_ack.txt'"; } # quoted: adb re-parses the line on the device
while kill -0 $FT 2>/dev/null; do
  SCENE=$(a shell run-as $PKG cat files/capture_scene.txt 2>/dev/null | tr -d '\r')
  if [ -n "$SCENE" ] && [ "$SCENE" != "$LAST" ]; then
    LAST="$SCENE"
    case "$SCENE" in
      done) ack done ;;
      hold:*) # hold:<name>:<x>:<y> — a real finger held down (physical pixels) while the screenshot is taken
        IFS=: read -r _ NAME HX HY <<< "$SCENE"
        a shell input motionevent DOWN "$HX" "$HY"
        sleep 1.2
        a exec-out screencap -p > "$OUTDIR/$THEME-$NAME.png"
        a shell input motionevent UP "$HX" "$HY"
        ack "$SCENE"
        echo "captured $NAME (held)" ;;
      clip_*)
        a shell screenrecord --time-limit 5 --bit-rate 6000000 /sdcard/$SCENE.mp4 &
        sleep 0.6 # the recorder is running before the action starts
        ack "$SCENE"
        echo "recording $SCENE" ;;
      *)
        a exec-out screencap -p > "$OUTDIR/$THEME-$SCENE.png"
        ack "$SCENE"
        echo "captured $SCENE" ;;
    esac
  fi
  sleep 0.2
done
sleep 5 # the last screen recording finishes
WOUT=$(cygpath -w "$OUTDIR" 2>/dev/null || echo "$OUTDIR") # adb.exe needs a Windows path (MSYS conversion is off)
for f in $(a shell ls /sdcard/ | tr -d '\r' | grep '^clip_.*\.mp4$'); do
  a pull /sdcard/$f "$WOUT/$THEME-$f" >/dev/null && a shell rm /sdcard/$f || echo "could not pull $f"
done
kill $GRANTER 2>/dev/null
a shell cmd uimode night no >/dev/null
grep -aE "All tests|Some tests|\[E\]" "build/ci-logs/capture-$THEME.txt"
ls "$OUTDIR" | grep "^$THEME-" | tr '\n' ' '; echo
