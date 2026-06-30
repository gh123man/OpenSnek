# DMG Release Setup

`OpenSnek` ships as a notarized GitHub Release DMG with a Finder install window (`OpenSnek.app` plus `/Applications` drag target).

## One-time Apple setup

1. In Apple Developer, confirm the bundle ID is `io.opensnek.OpenSnek`.
2. Create or download a `Developer ID Application` certificate for your team.
3. Export that certificate from Keychain Access as a password-protected `.p12`.
4. In App Store Connect, create an API key for notarization.

## GitHub secrets

Required repository secrets:

- `APPLE_DEVELOPER_ID_APP_CERT_BASE64`
- `APPLE_DEVELOPER_ID_APP_CERT_PASSWORD`
- `APPLE_DEVELOPER_TEAM_ID`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_API_KEY_P8`
- `OPEN_SNEK_SPARKLE_PUBLIC_ED_KEY`
- `OPEN_SNEK_SPARKLE_PRIVATE_ED_KEY`

Generate the Sparkle EdDSA key pair once with Sparkle's release tools:

```bash
gh release download 2.9.3 --repo sparkle-project/Sparkle --pattern Sparkle-2.9.3.tar.xz --dir /tmp/sparkle
tar -xf /tmp/sparkle/Sparkle-2.9.3.tar.xz -C /tmp/sparkle
/tmp/sparkle/bin/generate_keys
```

You can set them with:

```bash
./OpenSnek/scripts/prepare_release_secrets.sh \
  --cert /path/to/developer-id-application.p12 \
  --cert-password '<p12 password>' \
  --team-id '<APPLE_TEAM_ID>' \
  --notary-key /path/to/AuthKey_XXXX.p8 \
  --notary-key-id '<KEY_ID>' \
  --notary-issuer-id '<ISSUER_ID>' \
  --sparkle-public-key '<PUBLIC_ED_KEY>' \
  --sparkle-private-key '<PRIVATE_ED_KEY>' \
  --repo gh123man/OpenSnek \
  --apply
```

Without `--apply`, the script prints the `gh secret set ...` commands instead.

## Local release build

Build a signed DMG locally:

```bash
./OpenSnek/scripts/build_release_dmg.sh \
  --version 0.1.0 \
  --build-number 1 \
  --team-id '<APPLE_TEAM_ID>' \
  --notary-key-path /path/to/AuthKey_XXXX.p8 \
  --notary-key-id '<KEY_ID>' \
  --notary-issuer-id '<ISSUER_ID>'
```

Dry run without notarization:

```bash
./OpenSnek/scripts/build_release_dmg.sh \
  --version 0.1.0 \
  --build-number 1 \
  --team-id '<APPLE_TEAM_ID>' \
  --skip-notarize
```

Unsigned packaging-only dry run:

```bash
./OpenSnek/scripts/build_release_dmg.sh \
  --version 0.1.0 \
  --build-number 1 \
  --skip-sign \
  --skip-notarize
```

Output:

```text
OpenSnek/.release/artifacts/OpenSnek-<version>.dmg
OpenSnek/.release/artifacts/OpenSnek-<version>.zip
```

Logs and notarization output are written to:

```text
OpenSnek/.release/logs/
```

## GitHub Actions release flow

The workflow lives at `.github/workflows/release-dmg.yml`.

Preferred release entrypoint:

```bash
./OpenSnek/scripts/cut_release.sh --version <version>
```

Beta release entrypoint:

```bash
./OpenSnek/scripts/cut_release.sh --version <version>-beta.1
```

That script:
- fetches and fast-forwards `main`
- runs `swift test --package-path OpenSnek`
- creates an annotated `v<version>` tag
- pushes `main` and the tag

Versions with a prerelease suffix, such as `1.2.0-beta.1`, are published by the GitHub Actions workflow as GitHub prereleases with `latest=false`. OpenSnek checks GitHub's latest full release endpoint for update banners, so beta prereleases do not prompt existing stable users to update.

The GitHub Actions workflow can also be triggered manually by pushing a version tag:

```bash
git tag v<version>
git push origin v<version>
```

The workflow will:

1. verify the tagged commit is reachable from `main`
2. run `swift test --package-path OpenSnek`
3. import the Developer ID certificate into a temporary keychain
4. archive/export the app with Xcode
5. notarize and staple the `.app`
6. create a Sparkle update ZIP from the notarized `.app`
7. create a styled drag-install DMG, then sign, notarize, and staple it
8. generate a signed `appcast.xml` that points at the GitHub Release ZIP asset
9. publish the latest top section from `CHANGELOG.md` as the GitHub Release notes
10. upload `OpenSnek-<version>.dmg`, `OpenSnek-<version>.zip`, and `appcast.xml` to the matching GitHub Release
11. mark prerelease-suffix tags as GitHub prereleases instead of latest full releases

OpenSnek uses GitHub Releases as the Sparkle backend. The app feed URL is:

```text
https://github.com/gh123man/OpenSnek/releases/latest/download/appcast.xml
```

Stable releases are marked as GitHub's latest release, so existing users read the latest stable `appcast.xml`. Prerelease appcasts are uploaded to their prerelease tags but are not selected by the `/latest/download/` feed URL.

## Project generation check

The pull-request workflow installs XcodeGen and regenerates the Xcode project from `OpenSnek/project.yml` to catch spec regressions. The generated `OpenSnek/OpenSnek.xcodeproj` is not committed:

```bash
./OpenSnek/scripts/generate_xcodeproj.sh
```

## Validation

After a release build:

```bash
codesign --verify --deep --strict --verbose=2 "OpenSnek/.release/export/OpenSnek.app"
spctl -a -vv --type exec "OpenSnek/.release/export/OpenSnek.app"
xcrun stapler validate "OpenSnek/.release/export/OpenSnek.app"
xcrun stapler validate "OpenSnek/.release/artifacts/OpenSnek-<version>.dmg"
unzip -l "OpenSnek/.release/artifacts/OpenSnek-<version>.zip" | grep 'OpenSnek.app/Contents/Info.plist'
```
