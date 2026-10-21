# Native app links (operator runbook)

Atlas serves the iOS app-site association and Android Digital Asset Links files so
that links to supported Atlas pages open the native app. Both files fail closed:
they return 404 until the deployment lists verified app identities, and the app
then falls back to the browser. Only the hosted `atlas.tuist.dev` deployment
should configure them; the native apps request only that domain. Leave both unset
on self-hosted servers and in the demo (the demo configuration check rejects them).
`/open/...` and the dashboard's Open in Atlas action work everywhere through the
`dev.tuist.atlas` custom scheme without any of this setup.

## Claimed paths

`AtlasWeb.NativeLinks` is the source of truth. Exact matches only, with records as
one lowercase UUID segment:

- `/tasks`, `/commercial/sales/accounts`, `/commercial/sales/accounts/<uuid>`
- `/people`, `/people/time-off`, `/settings`
- `/open/{tasks,accounts,invoices,time-off,people,profile}`
- `/open/{tasks,accounts,invoices}/<uuid>`

`/commercial/finance` is never claimed. The Android manifest
(`atlas-native/android/AndroidManifest.xml`) must list the same paths; keep them in
sync when the allowlist changes.

## Apple

1. Enable the Associated Domains capability on the `U6LC622NKF.dev.tuist.atlas` App
   ID and regenerate the Atlas ad-hoc provisioning profile. The iOS distribution
   script refuses to sign without it, so nightly iOS publication stops until the
   profile is regenerated.
2. Set `ATLAS_APPLE_APP_IDS=U6LC622NKF.dev.tuist.atlas` in the hosted values.
   Malformed values (anything other than `TEAMID.bundle.id`, comma-separated) stop
   Atlas from booting.
3. Verify the origin and Apple's cached copy:

   ```sh
   curl -sS -D - https://atlas.tuist.dev/.well-known/apple-app-site-association
   curl -sS https://app-site-association.cdn-apple.com/a/v1/atlas.tuist.dev
   ```

   The origin must answer 200 with `application/json` and no redirect. Apple's CDN
   can take hours to pick up changes; test earlier on devices with developer mode
   and an `applinks:atlas.tuist.dev?mode=developer` development build.

## Android

App Links verification needs the SHA-256 fingerprint of a stable release-signing
certificate. Never configure a debug or per-build ephemeral key.

1. Generate the distribution keystore once and store it, its password and alias in
   1Password. Configure the protected `atlas-mobile-previews` GitHub environment with
   the keystore references, alias, and `ATLAS_ANDROID_APP_LINK_SHA256`. Until the
   keystore reference is set, nightly Android publication is skipped and CI keeps
   debug-signed artifacts only.
2. Set the server's `ATLAS_ANDROID_APP_LINK_SHA256` to the same value, formatted as
   uppercase colon-separated pairs (`AB:CD:...`, 32 pairs, comma-separated for
   several keys). The signing step refuses to publish an APK whose certificate is
   not in its list, so keep the CI and server values identical.
3. Rotating the key needs two independent steps. The server fingerprint list only
   controls which certificates may verify Atlas links; it does not let Android
   install an update signed by a different key. Installed apps accept the new key
   only through APK Signature Scheme v3 key rotation (a signing lineage produced with
   `apksigner rotate` and passed to `apksigner sign --lineage`). Without a lineage,
   people must uninstall and reinstall, losing the app's encrypted credentials and
   signing in again. Add the new fingerprint to the server before publishing the
   first build signed with it, keep both fingerprints while old installs remain, and
   remove the old one only after they have updated. With a lineage, `apksigner
   verify --print-certs` reports more than one signer, so check that the signing
   step still compares the certificate that verifies on current Android versions.
4. Verify:

   ```sh
   curl -sS -D - https://atlas.tuist.dev/.well-known/assetlinks.json
   adb shell pm verify-app-links --re-verify dev.tuist.atlas
   adb shell pm get-app-links dev.tuist.atlas
   ```

## Edge configuration

Apple's CDN and Google's verifier cannot solve bot challenges or follow redirects.
No new edge policy is needed: the existing `skip-sbfm-api-paths` Cloudflare rule
already exempts every non-`tuist.dev` host and all `/.well-known` paths from Super
Bot Fight Mode. Still verify after each deployment that the real edge answers both
association files with 200 `application/json` and no redirect (the `curl -D -`
checks above); a challenge or redirect fails verification silently and links keep
opening in the browser.
