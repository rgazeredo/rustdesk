#!/bin/bash
set -euo pipefail
build_root=/Volumes/SanDisk500/AZSign-build
input="$build_root/v28-source/flutter/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
output="$build_root/artifacts/AZSign-Remote-v28-capture-test-armv7.apk"
keystore=/Users/rga/Developer/azcode/azsign/instalador/azsign-rustdesk-release.jks
signer="$build_root/tools/android-sdk/build-tools/35.0.0/apksigner"
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
export PATH="$JAVA_HOME/bin:$PATH"
test -f "$input"
test -f "$keystore"
printf 'Assinar APK de teste AZSign Remote v28 (sem publicar).\n'
read -r -s -p 'Senha do keystore AZSign: ' AZSIGN_STORE_PASSWORD
printf '\n'
read -r -s -p 'Senha da chave (Enter para usar a mesma): ' AZSIGN_KEY_PASSWORD
printf '\n'
export AZSIGN_STORE_PASSWORD
export AZSIGN_KEY_PASSWORD="${AZSIGN_KEY_PASSWORD:-$AZSIGN_STORE_PASSWORD}"
trap 'unset AZSIGN_STORE_PASSWORD AZSIGN_KEY_PASSWORD' EXIT
"$signer" sign --ks "$keystore" --ks-key-alias azsign-rustdesk \
  --ks-pass env:AZSIGN_STORE_PASSWORD --key-pass env:AZSIGN_KEY_PASSWORD \
  --out "$output" "$input"
verification="$("$signer" verify --verbose --print-certs "$output")"
if ! printf '%s\n' "$verification" | grep -q 'becf9e8addbe567faaa67331f1ba0ca080c07e80f640f1ae404b58916cd547dc'; then
  printf 'Certificado inesperado. Não instalar.\n' >&2
  exit 1
fi
shasum -a 256 "$output"
printf 'Assinatura conferida. APK pronto para instalação no box.\n'
