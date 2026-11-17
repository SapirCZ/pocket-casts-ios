#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR="/Applications/Xcode-26.6.0.app/Contents/Developer"

echo "Xcode 26.6 first launch"
echo "macOS may ask for your Mac login password. It will not appear while typing."
echo "Apple's Xcode and SDK license will then be displayed for your review."
echo "Accept it only if you agree to the terms."
echo ""

sudo /usr/bin/env DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcodebuild -license
sudo /usr/bin/env DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcodebuild -runFirstLaunch

echo ""
echo "Xcode first launch completed. You can return to the project chat."
read -r -p "Press Return to close this window. " _
