#!/usr/bin/env bash
# Prepare an unsigned iPhone release and zip it as Payload/Runner.app.
# Bundle ID com.abaddon145.koreanMemo is fixed: a different ID installs a
# second app and the old local database is left behind.
set -euo pipefail

bundle_id="com.abaddon145.koreanMemo"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

prepare() {
  local pbx="ios/Runner.xcodeproj/project.pbxproj"
  if [[ ! -f "$pbx" ]]; then
    echo "missing $pbx; run flutter create first" >&2
    exit 1
  fi
  if ! grep -q "PRODUCT_BUNDLE_IDENTIFIER = ${bundle_id};" "$pbx"; then
    echo "Runner bundle ID is not ${bundle_id}" >&2
    exit 1
  fi

  # Free Apple IDs cannot sign Push, App Groups, iCloud, or Keychain Sharing.
  # The app stores its own Keychain item and does not share it, so the empty
  # keychain-access-groups entitlement from configure_device_storage is removed.
  rm -f ios/Runner/Runner.entitlements
  python3 - "$pbx" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
kept = [
    line
    for line in path.read_text().splitlines(True)
    if "CODE_SIGN_ENTITLEMENTS" not in line
]
path.write_text("".join(kept))
PY

  python3 - ios/Runner/Info.plist <<'PY'
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info["CFBundleDisplayName"] = "韩语记忆"
info["CFBundleName"] = "韩语记忆"
info.pop("UIBackgroundModes", None)
for key in (
    "aps-environment",
    "com.apple.security.application-groups",
    "com.apple.developer.associated-domains",
    "com.apple.developer.icloud-container-identifiers",
    "com.apple.developer.ubiquity-kvstore-identifier",
):
    info.pop(key, None)
path.write_bytes(plistlib.dumps(info))
PY

  python3 - pubspec.yaml <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
old = "assets/fonts/KoreanMemoSans-Regular.woff2"
new = "assets/fonts/KoreanMemoSans-Regular.otf"
if old not in text:
    raise SystemExit("pubspec is missing the WOFF2 font asset")
path.write_text(text.replace(old, new, 1))
PY

  if find ios -name '*.entitlements' | grep -q .; then
    echo "unexpected entitlements file left under ios/" >&2
    find ios -name '*.entitlements' >&2
    exit 1
  fi
  echo "prepared ${bundle_id} without restricted entitlements"
}

package() {
  local app=""
  local candidate
  for candidate in build/ios/iphoneos/Runner.app build/ios/Release-iphoneos/Runner.app; do
    if [[ -d "$candidate" ]]; then
      app="$candidate"
      break
    fi
  done
  if [[ -z "$app" ]]; then
    echo "Runner.app was not produced" >&2
    exit 1
  fi

  local built_id
  built_id="$(plutil -extract CFBundleIdentifier raw -o - "$app/Info.plist")"
  if [[ "$built_id" != "$bundle_id" ]]; then
    echo "built bundle ID is ${built_id}, expected ${bundle_id}" >&2
    exit 1
  fi
  local display
  display="$(plutil -extract CFBundleDisplayName raw -o - "$app/Info.plist")"
  if [[ "$display" != "韩语记忆" ]]; then
    echo "display name is ${display}" >&2
    exit 1
  fi

  rm -f "$app/embedded.mobileprovision"
  if find "$app" \( -name '*.entitlements' -o -name '*.xcent' -o -name '*.mobileprovision' \) | grep -q .; then
    echo "built app still contains an entitlement or profile" >&2
    find "$app" \( -name '*.entitlements' -o -name '*.xcent' -o -name '*.mobileprovision' \) >&2
    exit 1
  fi

  local version name stage ipa size
  version="$(awk '/^version:/ { print $2; exit }' pubspec.yaml)"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
    echo "unexpected pubspec version: ${version}" >&2
    exit 1
  fi
  name="KoreanMemo-${version}"
  stage="$(mktemp -d)"
  mkdir -p "$stage/Payload"
  cp -R "$app" "$stage/Payload/Runner.app"
  mkdir -p build
  ipa="$root/build/${name}.ipa"
  rm -f "$ipa"
  (
    cd "$stage"
    zip -r -y -q "$ipa" Payload
  )
  rm -rf "$stage"

  if ! unzip -l "$ipa" | grep -q 'Payload/Runner.app/Info.plist'; then
    echo "ipa is missing Payload/Runner.app" >&2
    exit 1
  fi
  size="$(wc -c < "$ipa" | tr -d ' ')"
  if (( size < 5000000 || size > 200000000 )); then
    echo "unexpected ipa size: ${size} bytes" >&2
    exit 1
  fi
  printf '%s\n' "$name" > build/ipa-artifact-name.txt
  printf '%s\n' "$ipa" > build/ipa-path.txt
  echo "ipa ${ipa} (${size} bytes)"
  shasum -a 256 "$ipa"
}

case "${1:-}" in
  prepare) prepare ;;
  package) package ;;
  *)
    echo "usage: bash tool/ios_unsigned_ipa.sh prepare|package" >&2
    exit 2
    ;;
esac
