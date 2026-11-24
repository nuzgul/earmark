#!/usr/bin/env bash
# Runs the integration tests on an iOS simulator (macOS; CI uses it). The engine records its
# debug-only test tone, so no microphone or permission prompt is involved.
# Usage (from app/):  tool/integration_ios.sh [extra flutter test args]
set -euo pipefail
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
xcrun simctl bootstatus "$UDID" -b
flutter test "${TARGET:-integration_test}" -d "$UDID" "$@"
