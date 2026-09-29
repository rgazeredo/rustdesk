#!/usr/bin/env bash
set -euo pipefail
# Package an already signed app without changing its identity or resources.
test "$(uname -s)" = Darwin
app=${1:?Pass the signed AZSign Remote.app path}
output=${2:?Pass a new DMG output path}
test -d "$app"
test ! -e "$output"
codesign --verify --deep --strict "$app"
package_tmp=$(mktemp -d "${TMPDIR:-/tmp}/azsign-remote-dmg.XXXXXX")
ditto "$app" "$package_tmp/AZSign Remote.app"
ln -s /Applications "$package_tmp/Applications"
test "$(readlink "$package_tmp/Applications")" = /Applications
hdiutil create -volname 'AZSign Remote' -srcfolder "$package_tmp" -format UDZO "$output"
hdiutil verify "$output"
echo "DMG created with Applications shortcut. Staging: $package_tmp"
