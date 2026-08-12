#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CORE_DIR=${1:-"$ROOT_DIR/../Olcrtc_manager"}
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Release-iphoneos"
APP_PATH="$APP_DIR/olcRTC.app"
IPA_PATH="$BUILD_DIR/olcrtc-ios-unsigned.ipa"

for command_name in go gomobile gobind xcodebuild xcodegen zip; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command not found: $command_name" >&2
        exit 1
    }
done

test -f "$CORE_DIR/go.mod" || {
    echo "olcRTC core not found at: $CORE_DIR" >&2
    exit 1
}

rm -rf "$ROOT_DIR/Olcrtc.xcframework" "$ROOT_DIR/OlcrtcIOS.xcodeproj" "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Building olcRTC XCFramework from $CORE_DIR"
(
    cd "$CORE_DIR"
    gomobile bind \
        -target=ios \
        -iosversion=16.0 \
        -trimpath \
        -ldflags="-s -w -checklinkname=0" \
        -o "$ROOT_DIR/Olcrtc.xcframework" \
        ./mobile
)

echo "Generating Xcode project"
(
    cd "$ROOT_DIR"
    xcodegen generate
)

echo "Building unsigned device application"
xcodebuild \
    -project "$ROOT_DIR/OlcrtcIOS.xcodeproj" \
    -scheme OlcrtcIOS \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    CONFIGURATION_BUILD_DIR="$APP_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    build

test -d "$APP_PATH" || {
    echo "Application was not produced at: $APP_PATH" >&2
    exit 1
}

echo "Packaging unsigned IPA"
PACKAGE_DIR=$(mktemp -d)
trap 'rm -rf "$PACKAGE_DIR"' EXIT INT TERM
mkdir -p "$PACKAGE_DIR/Payload"
cp -R "$APP_PATH" "$PACKAGE_DIR/Payload/"

codesign --remove-signature "$PACKAGE_DIR/Payload/olcRTC.app/olcRTC" 2>/dev/null || true
if test -d "$PACKAGE_DIR/Payload/olcRTC.app/Frameworks"; then
    find "$PACKAGE_DIR/Payload/olcRTC.app/Frameworks" -type f -perm -111 \
        -exec codesign --remove-signature {} \; 2>/dev/null || true
fi

(
    cd "$PACKAGE_DIR"
    zip -qry "$IPA_PATH" Payload
)

echo "Created $IPA_PATH"
shasum -a 256 "$IPA_PATH"
