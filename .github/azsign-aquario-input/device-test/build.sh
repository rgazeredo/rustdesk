#!/bin/sh
set -eu
sdk=${AZSIGN_ANDROID_SDK:?Set AZSIGN_ANDROID_SDK to the Android SDK directory}
tools="$sdk/build-tools/${AZSIGN_BUILD_TOOLS:-35.0.0}"
android="$sdk/platforms/${AZSIGN_ANDROID_PLATFORM:-android-34}/android.jar"
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=$(mktemp -d "${TMPDIR:-/tmp}/azsign-aquario-test.XXXXXX")
mkdir -p "$output/classes" "$output/dex"
"$tools/aapt" package -f -M "$source_dir/AndroidManifest.xml" -S "$source_dir/res" -I "$android" -F "$output/unsigned.apk"
javac -source 8 -target 8 -classpath "$android" -d "$output/classes" "$source_dir"/src/br/com/azsign/gestureprobe/*.java "$source_dir/../AquarioNodeClick.java"
"$tools/d8" --min-api 26 --lib "$android" --output "$output/dex" "$output"/classes/br/com/azsign/gestureprobe/*.class "$output"/classes/com/carriez/flutter_hbb/*.class
zip -j "$output/unsigned.apk" "$output/dex/classes.dex"
"$tools/zipalign" -f 4 "$output/unsigned.apk" "$output/aligned.apk"
"$tools/apksigner" sign --ks "${AZSIGN_TEST_KEYSTORE:?Set AZSIGN_TEST_KEYSTORE to a test-only debug keystore}" --ks-pass pass:android --out "$output/probe.apk" "$output/aligned.apk"
echo "Test APK: $output/probe.apk"
