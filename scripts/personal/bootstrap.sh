#!/bin/bash
# Build the personal staging app using its pinned Xcode.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT"
REQUIRED_XCODE="$(tr -d '[:space:]' < .xcode-version)"

matches_required_xcode() {
    local version
    version="$(DEVELOPER_DIR="$1" /usr/bin/xcodebuild -version 2>/dev/null | /usr/bin/awk 'NR == 1 { print $2 }')"
    case "$version" in
        "$REQUIRED_XCODE"|"$REQUIRED_XCODE".*) return 0 ;;
        *) return 1 ;;
    esac
}

if [ -n "${DEVELOPER_DIR:-}" ]; then
    if ! matches_required_xcode "$DEVELOPER_DIR"; then
        echo "DEVELOPER_DIR must point to Xcode $REQUIRED_XCODE." >&2
        exit 2
    fi
else
    for app in /Applications/Xcode*.app; do
        candidate="$app/Contents/Developer"
        if [ -d "$candidate" ] && matches_required_xcode "$candidate"; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi

if [ -z "${DEVELOPER_DIR:-}" ]; then
    echo "Install Xcode $REQUIRED_XCODE Universal and complete its first launch." >&2
    echo "Apple downloads: https://developer.apple.com/download/all/" >&2
    exit 2
fi

/usr/bin/xcodebuild -version
if ! /usr/bin/xcodebuild -checkFirstLaunchStatus; then
    echo "Complete the Xcode license and first launch in Terminal:" >&2
    echo "  open scripts/personal/xcode-first-launch.command" >&2
    exit 2
fi
if ! /usr/bin/xcrun --sdk iphonesimulator --show-sdk-path >/dev/null; then
    echo "Install the iOS platform support in Xcode before building." >&2
    exit 2
fi

if [ ! -f podcasts/Credentials/LocalApiCredentials.swift ]; then
    make external_contributor
fi
mkdir -p artifacts
make build_staging 2>&1 | tee artifacts/personal-build.log
