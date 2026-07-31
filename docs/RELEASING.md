# Publishing a macOS release

Pushing a version tag such as `v0.1.0` builds a DMG and publishes it as a
GitHub release. The workflow always builds and ad-hoc signs the app. For a
normal double-click installation on other Macs, configure Developer ID signing
and notarization first.

Add these GitHub Actions repository secrets:

- `MACOS_CERTIFICATE`: base64-encoded Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: password used when exporting the `.p12`
- `MACOS_SIGNING_IDENTITY`: full identity, such as
  `Developer ID Application: Example Name (TEAMID)`
- `KEYCHAIN_PASSWORD`: a temporary workflow keychain password
- `APPLE_ID`: Apple developer account email
- `APPLE_TEAM_ID`: Apple Developer team identifier
- `APPLE_APP_PASSWORD`: app-specific password used by `notarytool`

Then publish:

```sh
git tag v0.1.0
git push origin v0.1.0
```

For a local preview package:

```sh
make release
```

The DMG and its SHA-256 checksum are written under `dist/`.
