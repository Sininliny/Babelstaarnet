# Publishing a macOS release

Pushing a version tag such as `v0.4.0` builds a ZIP containing
`Babelstaarnet.app` and publishes it with a SHA-256 checksum. The workflow
always builds and at least ad-hoc signs the app. For a normal double-click
installation on other Macs, configure Developer ID signing and notarization
first.

There is deliberately no DMG. A disk image is the right shape for an app that
opens with a double click, and without a paid Apple Developer ID this one
cannot: whichever container it arrives in, the first launch is a Control-click
and an **Open**. The DMG only added a second download of the same bytes, a
second checksum, and a mount step in front of the same warning. Bring it back
on the day the app is notarized.

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
git tag v0.4.0
git push origin v0.4.0
```

For a local preview package:

```sh
make release
```

The `.app.zip` and its SHA-256 checksum are written under `dist/`.

Without a paid Apple Developer account the download is ad-hoc signed and cannot
be notarized, so macOS requires Control-clicking the extracted app, choosing
**Open**, and confirming once.
