#!/bin/sh
# Builds mac/build/Earshot.app
#
# Signing: if a code-signing certificate named "Earshot Local" (or the name in
# $EARSHOT_SIGN_IDENTITY) exists in your keychain, the app is signed with it.
# macOS then recognises every rebuild as the same app and keeps its permissions.
# Without one the app is ad-hoc signed, which works but makes macOS treat each
# rebuild as a new app. See the README for how to create the certificate.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Earshot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Earshot "$APP/Contents/MacOS/Earshot"
cp Info.plist "$APP/Contents/Info.plist"

IDENTITY="${EARSHOT_SIGN_IDENTITY:-Earshot Local}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\"" \
    && codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null; then
    echo "Signed with \"$IDENTITY\""
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed (no \"$IDENTITY\" certificate found)"
fi
echo "Built $APP"
