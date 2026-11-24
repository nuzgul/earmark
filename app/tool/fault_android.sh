#!/usr/bin/env bash
# Fault injection on a device (debug build, test tone, no microphone):
#   - five quick Record/Stop cycles, then the crash log must be empty;
#   - while recording: wake lock held, frame timing measured;
#   - kill -9 mid-recording, relaunch, and recovery must keep the audio (< 0.5 s lost) and the mark;
#   - the app is then stopped and the test app uninstalled (it was not on the device before),
#     unless KEEP=1.
# The test writes files/fault_ready.txt and files/fault_cycles.txt in the app's own storage: on a
# device, integration-test prints go to the PC, not to the device log.
# Usage (Git Bash, from app/):  tool/fault_android.sh <device-id>
set -u
export MSYS_NO_PATHCONV=1
ADB="${ADB:-adb}"
command -v "$ADB" >/dev/null || ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
D="${1:?device id}"
PKG=app.earmark.recorder
OUT=build/ci-logs
mkdir -p "$OUT"
a() { "$ADB" -s "$D" "$@"; }
clean() { tr -d '\r'; }

# The real app (lib/main.dart, which recovers at start): installed over the test build after the
# kill, as a user would reopen Earmark. Same debug signing, so the recording files stay.
echo "== building the real app"
flutter build apk --debug > "$OUT/fault-build.txt" 2>&1 || { echo "FAIL: build"; exit 1; }
cp build/app/outputs/flutter-apk/app-debug.apk "$OUT/app-main.apk"

(while true; do a shell pm grant $PKG android.permission.RECORD_AUDIO 2>/dev/null && a shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null; sleep 1; done) &
GRANTER=$!
a shell input keyevent KEYCODE_WAKEUP
a logcat -c
a logcat -b crash -c 2>/dev/null
a shell run-as $PKG rm -f files/fault_ready.txt files/fault_cycles.txt 2>/dev/null

flutter test integration_test/fault_test.dart -d "$D" > "$OUT/fault-flutter.txt" 2>&1 &
FT=$!

echo "== waiting for the recording"
READY=""
for i in $(seq 1 600); do
  READY=$(a shell run-as $PKG cat files/fault_ready.txt 2>/dev/null | clean)
  case "$READY" in id=*) break ;; esac
  READY=""
  sleep 1
done
if [ -z "$READY" ]; then
  echo "FAIL: no fault_ready.txt"
  kill $FT $GRANTER 2>/dev/null
  exit 1
fi
echo "$READY"
CYCLES=$(a shell run-as $PKG cat files/fault_cycles.txt 2>/dev/null | clean)
CRASH=$(a logcat -d -b crash 2>/dev/null | grep -c "$PKG")
echo "RESULT five Record/Stop cycles: ${CYCLES:-not done}; crash-log lines for $PKG: $CRASH"

a shell dumpsys gfxinfo $PKG reset >/dev/null
sleep 10 # live Record screen: heartbeat 4 Hz + level line
echo "RESULT wake lock while recording: $(a shell dumpsys power | grep -c 'Earmark:recording')"
a shell dumpsys gfxinfo $PKG | grep -E "Total frames rendered|Janky frames|50th percentile|90th percentile|99th percentile" | sed 's/^/RESULT frames: /'

ID=$(echo "$READY" | sed -E 's/.*id=([^ ]+).*/\1/')
POS=$(echo "$READY" | sed -E 's/.*pos=([0-9]+).*/\1/')
READY_T=$(echo "$READY" | sed -E 's/.*at=([0-9]+).*/\1/')
PID=$(a shell pidof $PKG | clean)
KILL_T=$(a shell date +%s%3N | clean)
a shell run-as $PKG kill -9 "$PID"
sleep 2
kill $FT 2>/dev/null
echo "== killed pid $PID; files left:"
a shell run-as $PKG ls -l files/recordings/"$ID" | sed 's/^/  /'

if [ "${DAMAGE:-0}" = 1 ]; then
  # Power-loss style damage: meta.json gone, and 2 KB of zeros mid-file (covers at least one
  # ADTS header, so the scan stops there). Recovery must rebuild meta and keep the unread rest.
  echo "== damaging: meta.json removed, 2 KB zeroed at byte 100000"
  a shell run-as $PKG rm files/recordings/"$ID"/meta.json
  a shell run-as $PKG dd if=/dev/zero of=files/recordings/"$ID"/audio.aac.part bs=1 seek=100000 count=2048 conv=notrunc 2>/dev/null
fi

echo "== installing the real app over the test build and reopening it"
a install -r "$OUT/app-main.apk" >/dev/null
a shell am start -W -n $PKG/.MainActivity >/dev/null
for i in $(seq 1 30); do # recovery runs at start
  a shell run-as $PKG ls files/recordings/"$ID"/audio.m4a >/dev/null 2>&1 && break
  sleep 1
done
sleep 2
META=$(a shell run-as $PKG cat files/recordings/"$ID"/meta.json | clean)
MARKS=$(a shell run-as $PKG cat files/recordings/"$ID"/marks.jsonl | grep -c '"kind":"user"')
FILES=$(a shell run-as $PKG ls files/recordings/"$ID" | clean | tr '\n' ' ')
python - "$META" "$POS" "$READY_T" "$KILL_T" "$MARKS" "$FILES" <<'PY'
import json, sys
meta, pos, ready, kill, marks, files = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6]
m = json.loads(meta)
expected = pos + (kill - ready)  # device epoch ms on both sides
lost = expected - m['duration_ms']
print(f"RESULT recovered: status={m['status']} duration={m['duration_ms']} ms, expected about {expected} ms, lost {lost} ms (target < 500); user marks kept: {marks}; files: {files}")
PY

echo "RESULT crash log after recovery: $(a logcat -d -b crash 2>/dev/null | grep -c "$PKG") lines; ANR: $(a logcat -d 2>/dev/null | grep -c "ANR in $PKG")"
kill $GRANTER 2>/dev/null
a shell am force-stop $PKG
if [ "${KEEP:-0}" != 1 ]; then a uninstall $PKG >/dev/null && echo "test app removed"; fi
