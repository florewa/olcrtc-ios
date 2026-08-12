#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

test -d "$ROOT_DIR/Olcrtc.xcframework" || {
    echo "Run Scripts/build-ipa.sh first so Olcrtc.xcframework exists" >&2
    exit 1
}

test -d "$ROOT_DIR/OlcrtcIOS.xcodeproj" || (
    cd "$ROOT_DIR"
    xcodegen generate
)

SIMULATOR_ID=$(
    xcodebuild \
        -project "$ROOT_DIR/OlcrtcIOS.xcodeproj" \
        -scheme OlcrtcIOS \
        -showdestinations 2>/dev/null |
        awk -F'id:' '/platform:iOS Simulator/ && /OS:/ {
            split($2, fields, ",")
            gsub(/[[:space:]]/, "", fields[1])
            print fields[1]
            exit
        }'
)

test -n "$SIMULATOR_ID" || {
    echo "No concrete iOS Simulator destination is available" >&2
    exit 1
}

xcodebuild \
    -project "$ROOT_DIR/OlcrtcIOS.xcodeproj" \
    -scheme OlcrtcIOS \
    -sdk iphonesimulator \
    -destination "id=$SIMULATOR_ID" \
    CODE_SIGNING_ALLOWED=NO \
    test
