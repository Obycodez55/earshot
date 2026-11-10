#!/bin/sh
# Builds android/build/earshot.apk without Gradle.
set -e
cd "$(dirname "$0")"
SDK="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
BT="$SDK/build-tools/35.0.0"
JAR="$SDK/platforms/android-35/android.jar"
OUT=build
rm -rf "$OUT" && mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

"$BT/aapt2" compile --dir res -o "$OUT/res.zip"
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml --java "$OUT/gen" \
    -o "$OUT/base.apk" "$OUT/res.zip"

javac -nowarn -source 11 -target 11 -cp "$JAR" -d "$OUT/classes" \
    $(find src "$OUT/gen" -name '*.java') 2>&1 | grep -v "bootstrap class path\|^1 warning\|system modules" || true
"$BT/d8" --lib "$JAR" --min-api 29 --output "$OUT/dex" $(find "$OUT/classes" -name '*.class')

cp "$OUT/base.apk" "$OUT/unsigned.apk"
(cd "$OUT/dex" && zip -q ../unsigned.apk classes.dex)
"$BT/zipalign" -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"

KEY="$HOME/.android/earshot-debug.keystore"
if [ ! -f "$KEY" ]; then
    mkdir -p "$HOME/.android"
    keytool -genkeypair -keystore "$KEY" -storepass android -keypass android -alias earshot \
        -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Earshot" >/dev/null 2>&1
fi
"$BT/apksigner" sign --ks "$KEY" --ks-pass pass:android --key-pass pass:android \
    --out "$OUT/earshot.apk" "$OUT/aligned.apk"
echo "Built $OUT/earshot.apk"
