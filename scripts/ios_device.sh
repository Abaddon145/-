#!/usr/bin/env bash
# Mac-side helper for installing KoreanMemo on an iPhone.
# Does not contain a Team ID, certificate, or provisioning profile.
# See docs/ios-device-install.md.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

usage() {
  cat <<'EOF'
Usage: scripts/ios_device.sh <command>

  run [device-id]   Install and run on a connected iPhone (flutter run)
  config            Prepare the Xcode project (flutter build ios --config-only)
  ipa               Print Archive / IPA export commands. Does not sign or export.

Requires macOS, Xcode, and Flutter. Signing uses the Team you select in Xcode.
No Team ID, certificate, or provisioning profile is stored in this repository.
See docs/ios-device-install.md.
EOF
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS device builds require macOS with Xcode. This machine is $(uname -s)."
  echo "See docs/ios-device-install.md. The PWA fallback is https://abaddon145.github.io/-/"
  exit 1
fi

command -v flutter >/dev/null 2>&1 || {
  echo "flutter is not on PATH."
  exit 1
}
command -v xcodebuild >/dev/null 2>&1 || {
  echo "xcodebuild was not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
}

prepare() {
  flutter pub get
  dart run tool/configure_device_storage.dart
  dart run build_runner build --delete-conflicting-outputs
}

cmd="${1:-}"
case "$cmd" in
  run)
    prepare
    if [[ -n "${2:-}" ]]; then
      flutter run -d "$2"
    else
      flutter run
    fi
    ;;
  config)
    prepare
    flutter build ios --config-only
    echo "Open ios/Runner.xcworkspace and select your Signing Team. No IPA was exported."
    ;;
  ipa)
    cat <<'EOF'
This command does not export a signed device IPA.

1. Open ios/Runner.xcworkspace and select your Team under Signing & Capabilities.
   Do not commit the Team ID Xcode writes into project.pbxproj.
2. Connect the iPhone, enable Developer Mode (iOS 16+), then either:
     flutter run -d <device-id>
   or Product > Run in Xcode.
3. After that Team can sign on this Mac:
     flutter build ipa --export-method development
     flutter build ipa --export-method ad-hoc
     flutter build ipa --export-method app-store
   Or use Product > Archive > Distribute App.
   - Personal Team (free): about 7 days, then run again to refresh. No TestFlight.
   - Ad Hoc: Apple Developer Program plus the device UDID.
   - TestFlight / App Store: Apple Developer Program.

flutter build ios --release --no-codesign does not produce an installable device IPA.
Unsigned alternative: https://abaddon145.github.io/-/
EOF
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
