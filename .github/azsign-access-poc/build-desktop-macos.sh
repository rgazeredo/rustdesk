#!/usr/bin/env bash
set -euo pipefail

# Run from the fork root. Toolchain/cache paths are supplied by the caller.
# Prerequisites: Flutter 3.24.5 with the two existing workflow patches,
# vcpkg 9e593bb18ea69cc5095e012465dcd675a822ed0d dependencies for arm64-osx,
# flutter_rust_bridge_codegen 1.80.1, cargo-expand 1.0.95 and CocoaPods.
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
test -n "${VCPKG_ROOT:-}"
test -f src/flutter_ffi.rs
cms_origin="${1:-https://app.azsign.com.br}"
case "$cms_origin" in https://*) ;; *) echo 'An HTTPS CMS origin is required.' >&2; exit 1 ;; esac
node .github/azsign-access-poc/apply.mjs . --desktop
(
  cd flutter
  flutter --suppress-analytics pub get --enforce-lockfile
)
flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs \
  --dart-output ./flutter/lib/generated_bridge.dart \
  --c-output ./flutter/macos/Runner/bridge_generated.h
MACOSX_DEPLOYMENT_TARGET=12.3 cargo build --locked --release --lib --features flutter,azsign-access-poc
nm -gU target/release/liblibrustdesk.dylib | grep ' _azsign_native_access_enabled$'
(
  cd flutter
  FLUTTER_XCODE_ARCHS=arm64 \
  FLUTTER_XCODE_ONLY_ACTIVE_ARCH=YES \
  FLUTTER_XCODE_MACOSX_DEPLOYMENT_TARGET=12.3 \
  FLUTTER_XCODE_AZSIGN_PRODUCT_NAME="AZSign Remote" \
  FLUTTER_XCODE_AZSIGN_BUNDLE_IDENTIFIER=com.azsign.remote.pilot \
  FLUTTER_XCODE_RUSTDESK_URL_SCHEME=azsign-rustdesk-pilot \
  FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO \
  flutter --suppress-analytics build macos --release \
    --dart-define="AZSIGN_DESKTOP_CMS_ORIGIN=$cms_origin"
)
app="flutter/build/macos/Build/Products/Release/AZSign Remote.app"
test -d "$app"
codesign --force --deep --sign - --entitlements flutter/macos/Runner/Release.entitlements "$app"
codesign --verify --deep --strict "$app"
echo "Local ad-hoc pilot built: $app (not notarized, not installed, no production deployment)."
