#!/bin/sh
# Builds mac/build/Earshot.app
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Earshot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Earshot "$APP/Contents/MacOS/Earshot"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
