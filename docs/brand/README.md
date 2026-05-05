# Brand Assets

The AIMeter logo is intentionally simple: a dark macOS-style rounded tile with a centered blue usage meter.

- `aimeter-logo.svg` is the editable source for docs and repository previews.
- App icon PNGs are generated from `scripts/generate_app_icon.swift` into `Sources/AIMeter/Resources/Assets.xcassets/AppIcon.appiconset`.

Regenerate the app icon set with:

```bash
swift scripts/generate_app_icon.swift
```
