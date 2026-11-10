#!/bin/sh
# Builds Earshot, installs it to /Applications, sets it to open at login, and starts it.
set -e
cd "$(dirname "$0")"
./build.sh

DEST=/Applications/Earshot.app
if pgrep -x Earshot >/dev/null; then
    pkill -x Earshot || true          # the app stops its stream and tidies the phone on exit
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Earshot >/dev/null || break; sleep 0.5; done
fi
rm -rf "$DEST"
cp -R build/Earshot.app "$DEST"
open "$DEST" --args --enable-login-item
echo "Installed $DEST"
