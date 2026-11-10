#!/bin/bash
# Builds FlagSentry.app without Xcode: swiftc + ad-hoc signing with the sandbox entitlements.
# Override the bundle identifier with: BUNDLE_ID=com.yourname.FlagSentry ./build.sh
# Set the version with: VERSION=1.2.3 BUILD_NUMBER=42 ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="${BUNDLE_ID:-io.github.4yvi.FlagSentry}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/FlagSentry.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target "$(uname -m)-apple-macos13.0" \
  main.swift AppDelegate.swift Core.swift -o "$APP/Contents/MacOS/FlagSentry"

# Info.plist: add the required bundle keys to our Info.plist
cp Info.plist "$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
P="$APP/Contents/Info.plist"
set_key() { # key type value: Add, or Set if it already exists
  "$PB" -c "Add :$1 $2 $3" "$P" 2>/dev/null || "$PB" -c "Set :$1 $3" "$P"
}
set_key CFBundleExecutable string FlagSentry
set_key CFBundleIdentifier string "$BUNDLE_ID"
set_key CFBundleName string FlagSentry
set_key CFBundlePackageType string APPL
set_key CFBundleShortVersionString string "$VERSION"
set_key CFBundleVersion string "$BUILD_NUMBER"
set_key LSMinimumSystemVersion string 13.0

codesign --force --sign - --entitlements FlagSentry.entitlements "$APP"
echo "Done: $APP"
