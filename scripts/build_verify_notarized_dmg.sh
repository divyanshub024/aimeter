#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/dist/AIMeter.dmg}"

export DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-W2B7PMH9SQ}"
export NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-aimeter-notary}"

echo "Building and notarizing AIMeter DMG..."
"$ROOT_DIR/scripts/build_dmg.sh" --notarize

echo "Validating stapled notarization ticket..."
xcrun stapler validate "$DMG_PATH"

echo "Validating Gatekeeper acceptance..."
spctl -a -vv --type open --context context:primary-signature "$DMG_PATH"

echo "Verified notarized DMG: $DMG_PATH"
