#!/usr/bin/env bash
# Low-storage check on an EMULATOR (fills /data on purpose; refuses anything that is not an emulator).
# Usage (Git Bash, from app/):  tool/disk_android.sh emulator-5554
set -u
export MSYS_NO_PATHCONV=1
ADB="${ADB:-adb}"
command -v "$ADB" >/dev/null || ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
D="${1:?emulator id}"
PKG=app.earmark.recorder
a() { "$ADB" -s "$D" "$@"; }
[ "$(a shell getprop ro.kernel.qemu | tr -d '\r')" = 1 ] || { echo "refusing: $D is not an emulator"; exit 1; }
OUT=build/ci-logs
mkdir -p "$OUT"
(while true; do a shell pm grant $PKG android.permission.RECORD_AUDIO 2>/dev/null && a shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null; sleep 1; done) &
GRANTER=$!
a shell rm -f /data/local/tmp/fill
a shell run-as $PKG rm -f files/disk_ready.txt 2>/dev/null
flutter test integration_test/disk_test.dart -d "$D" > "$OUT/disk-flutter.txt" 2>&1 &
FT=$!
for i in $(seq 1 600); do
  a shell run-as $PKG cat files/disk_ready.txt >/dev/null 2>&1 && break
  sleep 1
done
FREE_K=$(a shell df -k /data | tail -1 | awk '{print $4}')
FILL_M=$(( FREE_K / 1024 - 40 ))
echo "free ${FREE_K} KB; filling ${FILL_M} MB to leave ~40 MB"
a shell dd if=/dev/zero of=/data/local/tmp/fill bs=1048576 count=$FILL_M 2>&1 | tail -1
wait $FT
STATUS=$?
grep -E "RESULT|All tests|Some tests|Expected|Actual|reason" "$OUT/disk-flutter.txt"
a shell rm -f /data/local/tmp/fill
echo "disk freed: $(a shell df -h /data | tail -1)"
kill $GRANTER 2>/dev/null
exit $STATUS
