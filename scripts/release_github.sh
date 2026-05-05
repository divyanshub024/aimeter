#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
PROJECT_FILE="$ROOT_DIR/AIMeter.xcodeproj"
DMG_PATH="$ROOT_DIR/dist/AIMeter.dmg"
APP_NAME="AIMeter"

usage() {
  cat <<'EOF'
Usage: scripts/release_github.sh VERSION

Builds, notarizes, tags, pushes, and publishes an AIMeter GitHub release.

VERSION may be passed with or without a leading "v":
  scripts/release_github.sh 0.2.0
  scripts/release_github.sh v0.2.0

Defaults for the maintainer machine:
  DEVELOPMENT_TEAM defaults to W2B7PMH9SQ
  NOTARYTOOL_PROFILE defaults to aimeter-notary

Override them when needed:
  DEVELOPMENT_TEAM=TEAMID NOTARYTOOL_PROFILE=profile scripts/release_github.sh 0.2.0

Optional:
  RELEASE_NOTES="Custom release notes" scripts/release_github.sh 0.2.0
  GITHUB_REPO=owner/repo scripts/release_github.sh 0.2.0
EOF
}

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

run() {
  echo "+ $*"
  "$@"
}

infer_github_repo() {
  local remote_url
  remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"

  if [[ "$remote_url" =~ ^https://github.com/([^/]+/[^/.]+)(\.git)?$ ]]; then
    printf "%s\n" "${BASH_REMATCH[1]}"
    return
  fi

  if [[ "$remote_url" =~ ^git@github.com:([^/]+/[^/.]+)(\.git)?$ ]]; then
    printf "%s\n" "${BASH_REMATCH[1]}"
    return
  fi

  echo "Could not infer GitHub repo from origin remote. Set GITHUB_REPO=owner/repo." >&2
  exit 1
}

ensure_clean_worktree() {
  if ! git -C "$ROOT_DIR" diff --quiet ||
     ! git -C "$ROOT_DIR" diff --cached --quiet ||
     [[ -n "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard)" ]]; then
    cat >&2 <<'EOF'
Release stopped because the git worktree is not clean.
Commit, stash, or discard local changes before running a release.
EOF
    git -C "$ROOT_DIR" status --short >&2
    exit 1
  fi

  local current_branch
  current_branch="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" != "main" ]]; then
    echo "Release stopped because the current branch is '$current_branch', not 'main'." >&2
    exit 1
  fi
}

update_project_version() {
  local version="$1"
  local build_number="$2"

  perl -0pi -e "s/MARKETING_VERSION:\\s*\"[^\"]+\"/MARKETING_VERSION: \"$version\"/" "$PROJECT_SPEC"
  perl -0pi -e "s/CURRENT_PROJECT_VERSION:\\s*[0-9]+/CURRENT_PROJECT_VERSION: $build_number/" "$PROJECT_SPEC"
}

version_to_build_number() {
  local version="$1"
  local major minor patch
  IFS=. read -r major minor patch <<<"$version"
  echo $((major * 10000 + minor * 100 + patch))
}

version_input="${1:-}"
if [[ -z "$version_input" || "$version_input" == "-h" || "$version_input" == "--help" ]]; then
  usage
  exit 0
fi

version="${version_input#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version '$version_input'. Use semantic version format like 0.2.0." >&2
  exit 1
fi

tag="v$version"
build_number="$(version_to_build_number "$version")"
github_repo="${GITHUB_REPO:-$(infer_github_repo)}"
release_notes="${RELEASE_NOTES:-$APP_NAME $tag release.}"

export DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-W2B7PMH9SQ}"
export NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-aimeter-notary}"

require_bin git
require_bin gh
require_bin perl
require_bin xcodebuild
require_bin xcodegen
require_bin xcrun
require_bin spctl

if [[ ! -f "$PROJECT_SPEC" ]]; then
  echo "Missing project spec: $PROJECT_SPEC" >&2
  exit 1
fi

ensure_clean_worktree

if git -C "$ROOT_DIR" rev-parse "$tag" >/dev/null 2>&1; then
  echo "Local tag already exists: $tag" >&2
  exit 1
fi

if git -C "$ROOT_DIR" ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  echo "Remote tag already exists: $tag" >&2
  exit 1
fi

echo "Preparing $APP_NAME $tag for $github_repo..."
update_project_version "$version" "$build_number"

run git -C "$ROOT_DIR" diff --check
(cd "$ROOT_DIR" && run xcodegen generate)
run xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$APP_NAME" \
  -destination "platform=macOS" \
  -derivedDataPath "$ROOT_DIR/.derived" \
  test

run git -C "$ROOT_DIR" add "$PROJECT_SPEC" "$PROJECT_FILE/project.pbxproj"
if ! git -C "$ROOT_DIR" diff --cached --quiet; then
  run git -C "$ROOT_DIR" commit -m "Release $tag"
else
  echo "Project version already matches $tag; no version commit needed."
fi

run "$ROOT_DIR/scripts/build_dmg.sh" --notarize
run xcrun stapler validate "$DMG_PATH"
run spctl -a -vv --type open --context context:primary-signature "$DMG_PATH"

run git -C "$ROOT_DIR" push origin main
run git -C "$ROOT_DIR" tag -a "$tag" -m "$APP_NAME $tag"
run git -C "$ROOT_DIR" push origin "$tag"

if gh release view "$tag" --repo "$github_repo" >/dev/null 2>&1; then
  run gh release upload "$tag" "$DMG_PATH" --repo "$github_repo" --clobber
else
  run gh release create "$tag" "$DMG_PATH" \
    --repo "$github_repo" \
    --title "$APP_NAME $tag" \
    --notes "$release_notes"
fi

echo "Release ready: https://github.com/$github_repo/releases/tag/$tag"
