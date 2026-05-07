#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/AIMeter.xcodeproj"
PROJECT_SPEC="$ROOT_DIR/project.yml"
SCHEME="AIMeter"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="$ROOT_DIR/.derived"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/AIMeter.app"
XCODEGEN_BIN="${XCODEGEN_BIN:-xcodegen}"

usage() {
  cat <<'EOF'
Usage: scripts/run_dev.sh [--skip-generate] [--clean] [--no-restart]

Generates the Xcode project, builds AIMeter in Debug, restarts the app,
and opens the fresh build in the menu bar.

Options:
  --skip-generate   Build using the existing AIMeter.xcodeproj.
  --clean           Clean the Debug build before building.
  --no-restart      Do not quit an already-running AIMeter before opening.
  -h, --help        Show this help.

Examples:
  scripts/run_dev.sh
  scripts/run_dev.sh --clean
EOF
}

SKIP_GENERATE=false
CLEAN=false
RESTART_RUNNING_APP=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-generate)
      SKIP_GENERATE=true
      shift
      ;;
    --clean)
      CLEAN=true
      shift
      ;;
    --no-restart)
      RESTART_RUNNING_APP=false
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

require_bin xcodebuild
require_bin open
if [[ "$RESTART_RUNNING_APP" == true ]]; then
  require_bin osascript
  require_bin pgrep
  require_bin pkill
fi

quit_running_app() {
  if ! pgrep -x "$SCHEME" >/dev/null 2>&1; then
    return
  fi

  echo "Quitting existing $SCHEME..."
  osascript -e 'tell application "AIMeter" to quit' >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x "$SCHEME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.2
  done

  echo "Existing $SCHEME did not quit cleanly; stopping it..."
  pkill -x "$SCHEME" >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x "$SCHEME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.2
  done
}

if [[ "$SKIP_GENERATE" == false ]]; then
  require_bin "$XCODEGEN_BIN"
  if [[ ! -f "$PROJECT_SPEC" ]]; then
    echo "Missing project spec at $PROJECT_SPEC" >&2
    exit 1
  fi

  echo "Generating Xcode project..."
  (cd "$ROOT_DIR" && "$XCODEGEN_BIN" generate)
fi

if [[ ! -d "$PROJECT_FILE" ]]; then
  echo "Missing Xcode project at $PROJECT_FILE" >&2
  exit 1
fi

if [[ "$CLEAN" == true ]]; then
  echo "Cleaning $SCHEME ($CONFIGURATION)..."
  (cd "$ROOT_DIR" && xcodebuild \
    -project "$(basename "$PROJECT_FILE")" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    clean)
fi

echo "Building $SCHEME ($CONFIGURATION)..."
(cd "$ROOT_DIR" && xcodebuild \
  -project "$(basename "$PROJECT_FILE")" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build)

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build did not produce $APP_PATH" >&2
  exit 1
fi

if [[ "$RESTART_RUNNING_APP" == true ]]; then
  quit_running_app
fi

echo "Opening $APP_PATH..."
open -n "$APP_PATH"

echo "AIMeter is running in the macOS menu bar."
