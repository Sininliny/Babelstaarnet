# Publishing a macOS release

Pushing a version tag such as `v0.2.0` builds both a DMG and a ZIP containing
`Babelstaarnet.app`, then publishes both with SHA-256 checksums. The workflow
always builds and at least ad-hoc signs the app. For a normal double-click
installation on other Macs, configure Developer ID signing and notarization
first.

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
git tag v0.2.0
git push origin v0.2.0
```

For a local preview package:

```sh
make release
```

The DMG, `.app.zip`, and their SHA-256 checksums are written under `dist/`.

Without a paid Apple Developer account, both downloads are ad-hoc signed and
cannot be notarized. The `.app.zip` is offered as a direct alternative to the
DMG, but macOS may still require Control-clicking the extracted app, choosing
**Open**, and confirming once.
