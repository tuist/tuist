# Standalone deployment support

- `../compose.yaml` runs PostgreSQL, a one-shot migration service, Atlas, and Caddy. Application keys and admission domain are required through `.env`; provider credentials remain optional for documentation evaluation.
- `Caddyfile` is bundled with each release. Caddy terminates encrypted browser connections; Atlas remains on the private Compose network.
- `../../infra/helm/atlas/test-agent-boundary.sh` provides rendering-only agent permission checks and is also run by `validate.sh`; it requires Helm, mikefarah yq v4, and jq and never contacts a cluster. Deployment validation pins those tools through mise and runs the check before building the image. In-process agents need no Kubernetes sandbox. Legacy namespace retention is described in `../../infra/helm/atlas/AGENTS.md`.
- `../../infra/helm/atlas/test-chatgpt-config.sh` checks managed ChatGPT client sourcing through the application ExternalSecret and `envFrom`, without hardcoded client values or standalone/demo leakage. It runs before the image build and in `validate.sh`, using the same offline Helm/yq/jq toolchain.
- `check-sandbox-retention.sh VALUES RELEASE RELEASE_NAMESPACE` is a read-only managed pre-upgrade guard. It compares the union of namespaces in the latest and last-deployed Helm manifests with the target chart render, so both disabling and renaming legacy objects require a live `keep` annotation before deletion, including after rollback or lost ownership annotations. Run it after release recovery. The release lookup uses explicit status filters supported by Helm 3 and 4, not the removed Helm 4 `--all` flag. `test-sandbox-retention.sh` exercises the guard with fake release state and argument-aware kubectl, including renames, malformed configuration, and failed/invalid lookups; it validates release-list arguments through the real Helm CLI's `--help` and never contacts a cluster.
- `validate.sh` exercises the built release through Compose and a disposable kind cluster, including migrations, readiness, and public documentation. It uses temporary configuration, an isolated Kubernetes configuration, and a cleanup trap. Never point it at a managed cluster.
- Set `ATLAS_SCREENSHOT_DIR` and optionally `ATLAS_CHROME_PATH` to capture desktop, mobile, and dark-theme documentation screenshots during Compose validation. Keep browser profiles temporary.
- Keep the public instructions in `../priv/docs/self-hosting.md` aligned with the files actually included in the release bundle.
- `test-demo-release.sh [RELEASE_PATH]` exercises a built production release against its own disposable local PostgreSQL instance: migrations and seeds, SELECT-only server boot, anonymous curated pages with the navbar demo badge, and rejection of production database names, unseeded/non-demo datasets, owner/column-level/inherited write privileges, and integration credentials. It requires PostgreSQL command-line tools, curl, and Python, and never contacts existing databases or a cluster. Build production assets and `MIX_ENV=prod mix release --overwrite` first.
- `demo.md` describes the isolated public read-only demo: standalone chart plus `values-demo.yaml`, dedicated database and SELECT-only serving role, separate migration credentials, fictional release seeds, and DNS/PostgreSQL-only egress. Never layer the managed production values or mount production credentials into it.
- Leave scheduler sizing to Erlang's processor and container quota detection unless the operator supplies `ERL_FLAGS`. Compose accepts the override in `.env`; Helm accepts it through `env.ERL_FLAGS`.

## Native app links

Only hosted `atlas.tuist.dev` should configure verified identities: the apps
request that domain alone. Leave both identity lists unset on self-hosted and
demo deployments; demo validation rejects them. Association files return 404
until configured. Custom-scheme `/open` and header actions still work on HTTPS
self-hosted servers without association setup.

`AtlasWeb.NativeLinks.claimed_paths/0` defines the claimed pages; keep the native
Android manifest synchronized. Exact pages and UUID-shaped records only, never
entire hierarchies or `/commercial/finance`. See the native
[link contract](../../atlas-native/README.md#object-navigation).

### Apple

1. Enable Associated Domains on App ID `U6LC622NKF.dev.tuist.atlas` and regenerate
   the Atlas ad-hoc provisioning profile. Device signing refuses to publish
   without it; Android and simulator publication remain independent.
2. Set `ATLAS_APPLE_APP_IDS=U6LC622NKF.dev.tuist.atlas` in hosted values. Lists may
   contain comma-separated `TEAMID.bundle.id` identities; malformed values stop
   Atlas from booting.
3. Check the origin and Apple's cached copy:

   ```sh
   curl -sS -D - https://atlas.tuist.dev/.well-known/apple-app-site-association
   curl -sS https://app-site-association.cdn-apple.com/a/v1/atlas.tuist.dev
   ```

   Apple's CDN can take hours to refresh. Earlier device testing requires
   developer mode and a development build using
   `applinks:atlas.tuist.dev?mode=developer`.

### Android

1. Provision a stable private distribution key once, never a CI debug key.
   Configure protected `atlas-mobile-previews` variables
   `ATLAS_ANDROID_KEYSTORE_REF`, `ATLAS_ANDROID_KEYSTORE_PASSWORD_REF`,
   `ATLAS_ANDROID_KEY_ALIAS`, and `ATLAS_ANDROID_APP_LINK_SHA256` as described in
   [Android distribution](../../atlas-native/android/distribution/AGENTS.md).
   Without a key reference, nightly Android publication is skipped; debug CI
   artifacts remain available.
2. Set the server's `ATLAS_ANDROID_APP_LINK_SHA256` to the same uppercase,
   colon-separated 32-byte SHA-256 certificate fingerprint. Comma-separated
   multiple fingerprints are supported. Signing refuses an APK whose certificate
   is not in the configured list. Keep CI and server values identical.
3. A trusted fingerprint only authorizes links, not APK update compatibility.
   Changing keys requires a valid APK Signature Scheme v3 signing lineage
   (`apksigner rotate` and `apksigner sign --lineage`) or uninstall/reinstall,
   losing encrypted credentials. The current signing script does not configure a
   lineage; add and verify rotation support before publishing a rotated key.
   Publish the new fingerprint before its first build; retain the old one while
   old installations remain. Debug-to-distribution installs also need uninstall.
4. Check the deployed association and installed stable-key build:

   ```sh
   curl -sS -D - https://atlas.tuist.dev/.well-known/assetlinks.json
   adb shell pm verify-app-links --re-verify dev.tuist.atlas
   adb shell pm get-app-links dev.tuist.atlas
   ```

### Edge and device verification

Association origins must return 200 `application/json`, without redirects or bot
challenges. Existing Cloudflare `skip-sbfm-api-paths` exempts non-`tuist.dev`
hosts and `/.well-known`; no additional rule is needed. Verify real edge responses
after deployment. Local fixtures and disposable signing keys do not prove OS
verification. Test installed apps and browser fallback on real devices; browser
context and user preferences may keep even verified links in the browser.
