# Changelog

All notable changes to AIMeter will be documented in this file.

This project follows semantic versioning while it is practical for a small macOS utility.

## [0.4.0] - 2026-05-07

### Added

- Claude support with an isolated local web session, URL validation, and usage parsing from Claude's usage settings page.
- Provider-aware dashboard state for tracking Cursor and Claude side by side.
- Claude usage cards for current session, All models, Claude Design, and reset timing when Claude exposes it.
- Start-at-login setting using macOS login items.
- Local development and notarized DMG verification helper scripts.

### Changed

- Menu bar progress now uses the highest connected provider usage percentage.
- Popover only shows connected providers and keeps a loading state visible while saved provider sessions are still being checked.
- Claude usage UI now renders a stable set of cards instead of changing shape while the page loads.

### Fixed

- Deduplicated repeated Claude usage rows so `All models` and `Claude Design` appear only once.
- Filtered Claude template and explanatory copy so it does not become bogus usage text.
- Prevented the first-run provider connection screen from flashing during startup loading.

## [0.3.0] - 2026-05-06

### Changed

- Replaced menu bar percentage text with a compact progress bar-only status item.
- Kept warning/disconnected states visible in the menu bar with a small status indicator.

## [0.1.0] - 2026-05-05

### Added

- Native macOS menu bar dashboard for Cursor usage.
- Cursor tracking for plan label, total usage, Auto usage, and API usage.
- Local WebKit connection window for Cursor sign-in.
- Background refresh coordinators with cached successful snapshots.
- Unit tests for parsers, settings persistence, coordinators, and dashboard state.
- DMG build script with optional notarization support.
- Public launch docs, screenshots, contribution guide, security policy, and GitHub templates.
- URL validation and host-filtered scraping so AIMeter only loads and parses expected Cursor pages.
