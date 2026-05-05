# Release Checklist

Use this checklist before publishing a public AIMeter release.

## Preflight

- Confirm `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
- Update `CHANGELOG.md` with the release date and final notes.
- Regenerate the Xcode project with `xcodegen generate`.
- Run the full test suite:

```bash
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -destination "platform=macOS" -derivedDataPath ./.derived test
```

- Build a local unsigned Release DMG for testing:

```bash
./scripts/build_dmg.sh
```

Unsigned local DMGs are only for development verification. They will trigger Gatekeeper warnings on other Macs.

## Notarization

Use a saved notary profile when possible:

```bash
DEVELOPMENT_TEAM=TEAMID1234 \
NOTARYTOOL_PROFILE=your-profile \
./scripts/build_dmg.sh --notarize
```

Before uploading, the script checks that the Release app is signed with a `Developer ID Application` certificate, has a secure timestamp, has hardened runtime enabled, and does not include the debug `get-task-allow` entitlement. It also signs the final compressed DMG before notarization.

The script staples and validates the notarization ticket. You can repeat those checks manually:

```bash
xcrun stapler validate dist/AIMeter.dmg
spctl -a -vv --type open --context context:primary-signature dist/AIMeter.dmg
```

After the script finishes, verify the app opens on a clean macOS account or VM before publishing.

## GitHub Release

- Create a tag such as `v0.1.0`.
- Attach `dist/AIMeter.dmg`.
- Include a short note that AIMeter uses unofficial Cursor web-session scraping and may need parser updates when Cursor changes its pages.
- Mention tested macOS and Xcode versions.
- Link to `SECURITY.md` for private vulnerability reporting.

## Screenshot Hygiene

Public screenshots must use synthetic or redacted usage data. Never publish personal Cursor account details, cookies, billing information, or live usage values.
