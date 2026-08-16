# Publishing a macOS release

Pushing a version tag such as `v0.4.0` builds a ZIP containing
`Babelstaarnet.app`, `Install Babelstaarnet.command`, and `Start Here.txt`, and
publishes it with a SHA-256 checksum. The workflow always builds and at least
ad-hoc signs the app. For a normal double-click installation on other Macs,
configure Developer ID signing and notarization first.

There is deliberately no DMG. A disk image is the right shape for an app that
opens with a double click, and without a paid Apple Developer ID this one does
not: it can be ad-hoc signed but not notarized, so whichever container it
arrives in, macOS holds it for the quarantine flag the browser attached to the
download. The DMG only added a second download of the same bytes, a second
checksum, and a mount step in front of the same warning. Bring it back on the
day the app is notarized.

What the archive carries instead is a plain-text installer, because the thing
standing between the reader and the app is a flag on a file rather than
anything wrong with the app: it copies the bundle to `/Applications`, clears
`com.apple.quarantine` from the copy, and opens it. A quarantined *script* is
not refused the way a quarantined *bundle* is — Terminal asks for a
confirmation and takes it — which is the only reason this works at all. It
verifies the signature before it clears the flag, and again after the copy, so
a damaged download is refused rather than installed.

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

The ZIP and its SHA-256 checksum are written under `dist/`.

To install a build on this Mac without going through a download at all:

```sh
make install
```

That puts `dist/Babelstaarnet.app` into `/Applications` and opens it. A bundle
built here was never downloaded, so it never carried a quarantine flag and
there is no warning to clear.

Without a paid Apple Developer account the download is ad-hoc signed and cannot
be notarized, so on another Mac the first launch needs either the bundled
installer or **System Settings → Privacy & Security → Open Anyway**. The
Control-click-and-**Open** route that earlier notes described was removed in
macOS 15, which is the oldest macOS this app supports; it is gone for every
user this app has.
