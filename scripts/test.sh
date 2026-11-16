#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# CLT 27 ships Swift Testing but its SwiftPM plugin discovery misses this directory.
DEVELOPER_PATH="$(xcode-select -p)"
TEST_PLUGIN="$DEVELOPER_PATH/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$TEST_PLUGIN" ]; then
    swift test -Xswiftc -load-plugin-library -Xswiftc "$TEST_PLUGIN" "$@"
else
    swift test "$@"
fi
