# Releasing Wisp

Releases are cut by pushing a `v*` tag, which triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml): it builds,
Developer-ID signs, notarizes, staples, packages a `.dmg`, and attaches
everything (plus `SHA256SUMS.txt`) to a GitHub Release.

```sh
# bump CFBundleShortVersionString / CFBundleVersion in Resources/Info.plist first
git tag v0.1.0
git push origin v0.1.0
```

## One-time setup: an Apple Developer ID

Friction-free downloads (double-click to open, no Gatekeeper warning) require an
**Apple Developer Program** membership ($99/yr) so you can sign with a
*Developer ID Application* certificate and notarize with Apple. Until you add the
secrets below, the release workflow won't run — but CI, local builds, and the
ad-hoc-signed app all work without it.

### Required repository secrets

Add these under **Settings → Secrets and variables → Actions**:

| Secret | What it is |
|---|---|
| `SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `DEV_ID_CERT_P12_BASE64` | Your Developer ID cert + private key exported as `.p12`, base64-encoded |
| `DEV_ID_CERT_PASSWORD` | Password you set on that `.p12` |
| `AC_API_KEY_ID` | App Store Connect API key id |
| `AC_API_ISSUER_ID` | App Store Connect API issuer id |
| `AC_API_KEY_P8_BASE64` | The `AuthKey_XXXX.p8`, base64-encoded |

Create the `.p12`:

```sh
# In Keychain Access, export your "Developer ID Application" cert (with its
# private key) to Certificates.p12, then:
base64 -i Certificates.p12 | pbcopy   # paste into DEV_ID_CERT_P12_BASE64
```

Create the App Store Connect API key at
<https://appstoreconnect.apple.com/access/integrations/api> (role: *Developer*),
download the `.p8`, then:

```sh
base64 -i AuthKey_XXXXXXXX.p8 | pbcopy  # paste into AC_API_KEY_P8_BASE64
```

## Doing it locally instead

With the same Developer ID set up in your login keychain:

```sh
Scripts/build-app.sh release
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="my-notary-profile" \
  Scripts/sign-notarize.sh
Scripts/make-dmg.sh
```

Store a notary profile once with:

```sh
xcrun notarytool store-credentials my-notary-profile \
  --key AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
```

## Updating the Homebrew cask

After a release, update [`Casks/wisp.rb`](../Casks/wisp.rb) in your tap repo
(`homebrew-tap`):

- bump `version`
- set `sha256` to the dmg hash from the release's `SHA256SUMS.txt`
