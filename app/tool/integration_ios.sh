#!/usr/bin/env bash
# Runs the integration tests on an iOS simulator (macOS; CI uses it). The engine records its
# debug-only test tone, so no microphone or permission prompt is involved.
# Each test file runs on its own with a time limit; on a hang the script saves a simulator
# screenshot, and the app's system log is kept in build/ci-logs/ either way.
# Usage (from app/):  tool/integration_ios.sh [test files...]
set -uo pipefail
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
ios = sorted((k for k in runtimes if ".iOS-" in k), key=lambda k: [int(x) for x in k.rsplit("iOS-", 1)[1].split("-")])
for k in reversed(ios):
    for d in runtimes[k]:
        if d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit()
sys.exit("no iPhone simulator")
')
echo "simulator $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
LOGS=build/ci-logs
mkdir -p "$LOGS"
xcrun simctl spawn "$UDID" log stream --style compact --level info --predicate 'process == "Runner"' > "$LOGS/runner.log" 2>&1 &
LOGGER=$!

run() { # file, limit in seconds
  local file=$1 limit=$2 name
  name=$(basename "$file" .dart)
  flutter test "$file" -d "$UDID" &
  local pid=$!
  for ((s = 0; s < limit; s += 5)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      return $?
    fi
    sleep 5
  done
  echo "TIMEOUT: $file still running after ${limit}s"
  xcrun simctl io "$UDID" screenshot "$LOGS/hang-$name.png" || true
  kill "$pid" 2>/dev/null
  sleep 3
  kill -9 "$pid" 2>/dev/null
  return 124
}

STATUS=0
FILES=("$@")
[ ${#FILES[@]} -eq 0 ] && FILES=(integration_test/clip_test.dart integration_test/owner_sequence_test.dart)
for f in "${FILES[@]}"; do
  run "$f" 420 || STATUS=1
done
kill "$LOGGER" 2>/dev/null
exit $STATUS
