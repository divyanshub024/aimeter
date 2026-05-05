# Contributing

## Local setup

Prerequisites:

- macOS 14+
- Xcode 26.2+
- Xcode command line tools
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

From the repository root:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -destination "platform=macOS" -derivedDataPath ./.derived build
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -destination "platform=macOS" -derivedDataPath ./.derived test
```

## Project structure

- `Sources/AIMeter/App`: app lifecycle and dependency wiring
- `Sources/AIMeter/Core`: shared models, coordinators, formatting, and parser helpers
- `Sources/AIMeter/Cursor`: Cursor web-session client, scraper, and parser
- `Sources/AIMeter/Storage`: settings persistence
- `Sources/AIMeter/UI`: menu bar, popover, and settings UI
- `Tests/AIMeterTests`: parser and coordinator coverage
- `docs`: release notes and public screenshots

## Code style

- Follow the style already used in nearby Swift files.
- Keep Cursor-specific parsing rules inside the Cursor parser.
- Put reusable parsing primitives in `DashboardParserSupport`.
- Prefer small, focused changes over broad refactors.
- Keep UI copy short and concrete; AIMeter is a utility, not a marketing page.

## Scraper-specific development notes

AIMeter reads usage from an authenticated web session using `WKWebView`. This integration is unofficial and may break when Cursor pages change.

When working on scraper bugs:

- prefer updating parser fixtures first
- keep parsing scoped to the known Cursor usage sections
- do not commit cookies, screenshots with personal data, or account details
- add tests for new Cursor page structures whenever possible

The settings UI intentionally hides developer-only URL override fields. The underlying override plumbing still exists in:

- `CursorSettings.usagePageURL`

If you need those overrides while debugging, re-expose them locally in `SettingsView.swift` or change defaults locally before opening a pull request.

## Pull requests

- keep changes focused
- include or update tests for parser/coordinator behavior
- update `README.md` when behavior or setup changes
- update `CHANGELOG.md` for user-visible changes
- do not commit generated artifacts such as `.derived/`, `.derived-release/`, or `dist/`

## Screenshots

Documentation screenshots in `docs/screenshots` use synthetic data. If you add or replace screenshots, redact all personal usage values, account identifiers, billing details, and provider session information before opening a pull request.
