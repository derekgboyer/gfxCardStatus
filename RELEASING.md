# Releasing gfxCardStatus

Pull requests and branch pushes run `.github/workflows/build.yml` (universal Release, ad-hoc signature, policy tests). Pushing a tag named `v*` runs `.github/workflows/release.yml` on a macOS runner. With none of the secrets below, that job still builds, ad-hoc signs, and uploads a zip, a DMG, source archives, `README.md`, and an unsigned `appcast.xml`.

Release signing uses `gfxCardStatus.entitlements`, which is empty, plus the hardened runtime. The app stays unsandboxed: GPU switching opens an IOKit user client. Do not put `com.apple.security.get-task-allow` in that file. Debug builds use `gfxCardStatusDebug.entitlements`, which turns off library validation so an ad-hoc local build can load Sparkle. Release builds do not.

The Developer ID job re-signs Sparkle inside-out, with a timestamp, in the order Sparkle documents for distribution outside Xcode's archive export. Stock Sparkle 2.6 and later do not sandbox `Downloader.xpc` unless `DOWNLOADER_SANDBOXED_ENTITLEMENTS` is turned on when Sparkle itself is built. This app does not set `SUEnableDownloaderService`, so that XPC service is not part of the update path. The workflow preserves whatever entitlements the XPC already has. It does not require `com.apple.security.app-sandbox`.

Add these under **Settings → Secrets and variables → Actions**.

## Variable

| Name | Required | Purpose |
| --- | --- | --- |
| `SPARKLE_PUBLIC_ED_KEY` | For update checks on a CI release | Bare base64 Ed25519 public key passed into the app as the `SPARKLE_PUBLIC_ED_KEY` build setting. A secret of the same name is used only when this variable is empty |

The public key is not a secret. Store it as a variable.

## Secrets

| Name | Required | Purpose |
| --- | --- | --- |
| `BUILD_CERTIFICATE_BASE64` | No | Base64 of a Developer ID Application `.p12` |
| `P12_PASSWORD` | With the certificate | Password for that `.p12` |
| `KEYCHAIN_PASSWORD` | No | Temporary keychain password on the runner. The workflow creates one if this is empty |
| `APPLE_API_KEY_ID` | No | App Store Connect API key id, for `notarytool` |
| `APPLE_API_ISSUER_ID` | No | App Store Connect issuer id |
| `APPLE_API_KEY` | No | Contents of the `AuthKey_<KEYID>.p8` file, including the BEGIN/END lines |
| `SPARKLE_PRIVATE_KEY` | For a signed appcast | Single-line base64 EdDSA private key passed to `generate_appcast` / `sign_update`. Never commit this, and do not store it in `SPARKLE_PUBLIC_ED_KEY` |
| `SPARKLE_PUBLIC_ED_KEY` | No | Fallback only, when the variable above is empty |

The release job publishes with the built-in `GITHUB_TOKEN` (`contents: write`). Do not create a personal access token for that.

Notarization runs only when the Developer ID certificate and all three App Store Connect secrets are present. The job then staples the app and the DMG. An appcast built without `SPARKLE_PRIVATE_KEY` has no EdDSA signature. Sparkle rejects that feed until a signed release is published.

## Developer ID certificate

In Keychain Access, select the **Developer ID Application** certificate and its private key. Choose **File → Export Items…**, format **Personal Information Exchange (.p12)**, and set a password.

On a Mac:

```sh
base64 -i DeveloperID.p12 | pbcopy
```

Paste that into `BUILD_CERTIFICATE_BASE64`. Put the `.p12` password in `P12_PASSWORD`.

If those two are absent, the workflow sets the codesign identity to `-` and says so in the log. It does not fail the release.

## App Store Connect API key

In App Store Connect, open **Users and Access → Integrations → App Store Connect API** and generate a key with the **Developer** role. Note the **Key ID** and the **Issuer ID**. Download `AuthKey_<KEYID>.p8` once.

- `APPLE_API_KEY_ID`: the Key ID
- `APPLE_API_ISSUER_ID`: the Issuer ID
- `APPLE_API_KEY`: the full `.p8` file contents

`script/dist` is separate. It still uses the Apple ID keychain item `AC_PASSWORD` and team `LF22FTQC25`. The Actions workflow uses the API key and does not read that keychain item.

## Sparkle EdDSA keys

The workflow downloads Sparkle **2.10.0** tools (the same major version the app links) and runs `generate_appcast` from that archive. Generate the key pair once, on a Mac, from that same archive:

```sh
curl -fsSL -o Sparkle-2.10.0.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz
mkdir Sparkle && tar -xf Sparkle-2.10.0.tar.xz -C Sparkle
Sparkle/bin/generate_keys
```

`generate_keys` prints the public key and stores the private key in the login keychain (account `ed25519`, service `https://sparkle-project.org`).

The `SPARKLE_PUBLIC_ED_KEY` variable is the bare base64 public key: the text inside the `<string>` element, not the surrounding `<key>SUPublicEDKey</key>` lines and not the private key. The release workflow also accepts that full snippet and extracts the key. It passes only the bare key to `xcodebuild`, which writes it to `SUPublicEDKey`. Xcode and `script/dist` do not read the variable. They keep the key in the Debug and Release build settings, currently `4duXTeQPGZRwAyOAG2Wvqjkuk23es7QEuuy9FcjPEao=`, and the feed `https://gfx.io/appcasts/$(SU_FEED_CHANNEL).xml`. Change those build settings only when local builds should match the GitHub feed.

Export the private key and store that single line of base64 as `SPARKLE_PRIVATE_KEY`:

```sh
security find-generic-password -a ed25519 -s "https://sparkle-project.org" -w
```

The workflow writes this secret to a temporary file for Sparkle's tools and does not print it. `generate_keys -x private-key-file` writes the same secret to a file. The public key inside the app and the private key that signs `appcast.xml` have to be the pair from the same `generate_keys` run. Do not commit the private key.

## Cut a release

`CFBundleVersion` is not edited by hand. A Run Script phase sets it to `5000` plus `git rev-list --count HEAD`. The workflows clone the full history so that number matches a local build of the same commit. Sparkle compares this build number, so it increases on every commit.

Bump `MARKETING_VERSION` in both the Debug and Release configurations when the version users see should change. It is `2.5` today. Commit that, then tag and push:

```sh
git tag v2.5
git push origin v2.5
```

The tag must match `v*`. The GitHub release title uses the tag. The app's short version and the asset names (`gfxCardStatus-2.5.zip`, `gfxCardStatus-2.5.dmg`, `gfxCardStatus-2.5-source.zip`, `gfxCardStatus-2.5-source.tar.gz`) come from `CFBundleShortVersionString`. The appcast enclosure is only the app zip. Source archives are uploaded beside it and are not update items.

The app built by the tag workflow uses:

`https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml`

Copies built by Xcode or `script/dist` still check `https://gfx.io`. Tagging a release does not move those installs onto the GitHub feed.
