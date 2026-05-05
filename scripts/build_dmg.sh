#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR"
PROJECT_FILE="$PROJECT_DIR/AIMeter.xcodeproj"
PROJECT_SPEC="$PROJECT_DIR/project.yml"
SCHEME="AIMeter"
APP_NAME="AIMeter"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$PROJECT_DIR/.derived-release"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d /tmp/aimeter-dmg.XXXXXX)"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"
DMG_RW_PATH="$DIST_DIR/${APP_NAME}-rw.dmg"
DMG_BACKGROUND_PATH="$STAGING_DIR/.background/installer-background.png"
DMG_MARKER_NAME=".aimeter-dmg-build"
DEVELOPER_ID_APPLICATION_IDENTITY=""

NOTARIZE=false
XCODEGEN_BIN="${XCODEGEN_BIN:-xcodegen}"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: scripts/build_dmg.sh [--notarize]

Builds a signed Release .app with Xcode, packages it into dist/AIMeter.dmg,
and optionally notarizes/staples the DMG.

Notarization options:
  1. Set NOTARYTOOL_PROFILE to a saved keychain profile name, or
  2. Set all of:
     APPLE_ID
     APPLE_TEAM_ID
     APPLE_APP_SPECIFIC_PASSWORD

Examples:
  scripts/build_dmg.sh
  DEVELOPMENT_TEAM=TEAMID NOTARYTOOL_PROFILE=my-notary scripts/build_dmg.sh --notarize
  APPLE_ID=me@example.com APPLE_TEAM_ID=TEAMID APPLE_APP_SPECIFIC_PASSWORD=xxxx scripts/build_dmg.sh --notarize
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notarize)
      NOTARIZE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_bin "$XCODEGEN_BIN"
require_bin xcodebuild
require_bin hdiutil
require_bin ditto
require_bin codesign
require_bin security
require_bin osascript
require_bin swift

if [[ "$NOTARIZE" == true ]]; then
  require_bin xcrun
  require_bin plutil
  require_bin spctl
fi

if [[ ! -f "$PROJECT_SPEC" ]]; then
  echo "Missing project spec at $PROJECT_SPEC" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
rm -f "$DMG_RW_PATH"

detach_existing_dmg_mounts() {
  local mounted_volume
  shopt -s nullglob
  for mounted_volume in /Volumes/"$APP_NAME" /Volumes/"$APP_NAME "*; do
    if [[ -f "$mounted_volume/$DMG_MARKER_NAME" ]]; then
      echo "Detaching existing AIMeter build volume at $mounted_volume..."
      hdiutil detach "$mounted_volume" >/dev/null || true
    fi
  done
  shopt -u nullglob
}

detach_existing_dmg_mounts

echo "Generating Xcode project..."
(cd "$PROJECT_DIR" && "$XCODEGEN_BIN" generate)

XCODEBUILD_SETTINGS=()
if [[ "$NOTARIZE" == true ]]; then
  identity_line="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 || true)"
  if [[ -z "$identity_line" ]]; then
    cat >&2 <<'EOF'
Notarization requires a "Developer ID Application" certificate in your login keychain.
Create or download it from Apple Developer > Certificates, Identifiers & Profiles > Certificates.
EOF
    exit 1
  fi
  DEVELOPER_ID_APPLICATION_IDENTITY="$(awk '{print $2}' <<<"$identity_line")"

  XCODEBUILD_SETTINGS+=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=Developer ID Application"
    ENABLE_HARDENED_RUNTIME=YES
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    "OTHER_CODE_SIGN_FLAGS=--timestamp"
  )

  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    XCODEBUILD_SETTINGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
  elif [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    XCODEBUILD_SETTINGS+=("DEVELOPMENT_TEAM=$APPLE_TEAM_ID")
  fi
fi

echo "Building $APP_NAME ($CONFIGURATION)..."
XCODEBUILD_COMMAND=(xcodebuild \
  -project "$(basename "$PROJECT_FILE")" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build)

if [[ ${#XCODEBUILD_SETTINGS[@]} -gt 0 ]]; then
  XCODEBUILD_COMMAND+=("${XCODEBUILD_SETTINGS[@]}")
fi

(cd "$PROJECT_DIR" && "${XCODEBUILD_COMMAND[@]}")

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build did not produce $APP_PATH" >&2
  exit 1
fi

verify_notarization_signature() {
  local sign_info
  local entitlements
  sign_info="$(mktemp /tmp/aimeter-signature.XXXXXX)"
  entitlements="$(mktemp /tmp/aimeter-entitlements.XXXXXX)"

  codesign --verify --strict --deep --verbose=2 "$APP_PATH"
  codesign --display --verbose=4 "$APP_PATH" >"$sign_info" 2>&1
  codesign --display --entitlements :- "$APP_PATH" >"$entitlements" 2>/dev/null || true

  if ! grep -q "Authority=Developer ID Application" "$sign_info"; then
    echo "Release app is not signed with a Developer ID Application certificate." >&2
    cat "$sign_info" >&2
    exit 1
  fi

  if ! grep -q "Timestamp=" "$sign_info"; then
    echo "Release app signature does not include a secure timestamp." >&2
    cat "$sign_info" >&2
    exit 1
  fi

  if ! grep -q "Runtime Version=" "$sign_info"; then
    echo "Release app does not have the hardened runtime enabled." >&2
    cat "$sign_info" >&2
    exit 1
  fi

  if grep -q "com.apple.security.get-task-allow" "$entitlements"; then
    echo "Release app still contains the debug get-task-allow entitlement." >&2
    cat "$entitlements" >&2
    exit 1
  fi
}

if [[ "$NOTARIZE" == true ]]; then
  echo "Verifying distribution signature..."
  verify_notarization_signature
fi

echo "Staging DMG contents..."
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
touch "$STAGING_DIR/$DMG_MARKER_NAME"
swift "$PROJECT_DIR/scripts/generate_dmg_background.swift" "$DMG_BACKGROUND_PATH"
chflags hidden "$STAGING_DIR/.background" || true
chflags hidden "$STAGING_DIR/$DMG_MARKER_NAME" || true

create_installer_dmg() {
  local mount_output
  local mount_dir
  local device_name
  local mounted_volume_name

  echo "Creating writable DMG layout..."
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -ov \
    -format UDRW \
    "$DMG_RW_PATH" >/dev/null

  mount_output="$(hdiutil attach "$DMG_RW_PATH" -readwrite -noverify -noautoopen)"
  device_name="$(printf "%s\n" "$mount_output" | awk '/\/Volumes\// {print $1; exit}')"
  mount_dir="$(printf "%s\n" "$mount_output" | sed -n 's|^/dev/[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*\(/Volumes/.*\)$|\1|p' | tail -n 1)"
  mounted_volume_name="$(basename "$mount_dir")"

  if [[ -z "$device_name" || -z "$mount_dir" ]]; then
    echo "Could not mount writable DMG for layout." >&2
    printf "%s\n" "$mount_output" >&2
    exit 1
  fi

  echo "Applying Finder window layout..."
  if ! osascript <<EOF
tell application "Finder"
  tell disk "$mounted_volume_name"
    open
    set current view of container window to icon view
    try
      set toolbar visible of container window to false
    end try
    try
      set statusbar visible of container window to false
    end try
    set the bounds of container window to {180, 120, 900, 540}

    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:installer-background.png"

    set position of item "$APP_NAME.app" of container window to {180, 205}
    set position of item "Applications" of container window to {540, 205}
    update without registering applications
    delay 3
    try
      close
    end try
    open
    update without registering applications
    delay 3
    try
      close
    end try
  end tell
end tell
EOF
  then
    echo "Warning: Finder layout could not be applied; continuing with a functional DMG." >&2
  fi

  sync
  hdiutil detach "$device_name" >/dev/null

  echo "Compressing final DMG at $DMG_PATH..."
  hdiutil convert "$DMG_RW_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" >/dev/null
  rm -f "$DMG_RW_PATH"
}

echo "Creating DMG at $DMG_PATH..."
create_installer_dmg

sign_final_dmg() {
  echo "Signing final DMG..."
  codesign --force --sign "$DEVELOPER_ID_APPLICATION_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"
}

notarize_dmg() {
  echo "Submitting DMG for notarization..."
  local notary_args=()
  local submission_json
  local submission_id
  local status
  submission_json="$(mktemp /tmp/aimeter-notary-submit.XXXXXX)"

  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$NOTARYTOOL_PROFILE")
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    notary_args=(
      --apple-id "$APPLE_ID"
      --team-id "$APPLE_TEAM_ID"
      --password "$APPLE_APP_SPECIFIC_PASSWORD"
    )
  else
    cat >&2 <<'EOF'
Notarization requested, but no credentials were provided.
Set NOTARYTOOL_PROFILE, or set APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD.
EOF
    exit 1
  fi

  xcrun notarytool submit "$DMG_PATH" \
    "${notary_args[@]}" \
    --wait \
    --output-format json | tee "$submission_json"

  submission_id="$(plutil -extract id raw -o - "$submission_json")"
  status="$(plutil -extract status raw -o - "$submission_json")"

  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed with status: $status" >&2
    if [[ -n "$submission_id" ]]; then
      echo "Fetching notarization log for $submission_id..." >&2
      xcrun notarytool log "$submission_id" "${notary_args[@]}" >&2 || true
    fi
    exit 1
  fi

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl -a -vv --type open --context context:primary-signature "$DMG_PATH"
}

if [[ "$NOTARIZE" == true ]]; then
  sign_final_dmg
  notarize_dmg
fi

echo "DMG ready: $DMG_PATH"
