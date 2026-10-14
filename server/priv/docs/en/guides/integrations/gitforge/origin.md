---
{
  "title": "Cursor Origin",
  "titleTemplate": ":title · Git forges · Integrations · Guides · Tuist",
  "description": "Connect native Cursor Origin repositories to Tuist PR reports, bundle-size checks, and Tuist-hosted Buildkite runners."
}
---
# Cursor Origin {#cursor-origin}

Origin is Cursor's code-hosting service. Its forge apps are separate from the [Tuist coding-agent plugin](https://cursor.com/marketplace/tuist).

## Connect a repository {#connect-a-repository}

1. Open **Settings → Integrations** in the Tuist account that owns your project and select **Install Origin App**. The card is available when the server has an Origin App configured.
2. Approve the installation in Origin, choosing the namespace and repositories Tuist may access.
3. Back in Tuist, confirm the selected account. If you started in Origin's app directory, sign in and switch to your organization's account before confirming. Installation approval expires after five minutes; install again if it expires during sign-in.
4. Choose a Tuist project and a native Origin repository, then select **Connect repository**. Each project connects to one forge repository.

Tuist uses the installation's accessible repositories, not a manually entered clone URL. Suspension stops feedback. Removing repository access removes the project connection on the next installation webhook. **Disconnect Origin** revokes the Origin installation and removes its Tuist project connections.

## Pull request feedback {#pull-request-feedback}

Tuist updates a project-specific PR comment containing the same run report as GitHub: previews and their QR codes, builds, test runs, failed and flaky tests, and bundles, where those reports are available. Keep using your normal Tuist reporting commands in CI. Buildkite identifies PR runs with `refs/pull/<number>/merge`; the reported origin remote must match the connected Origin repository.

Bundle-size thresholds publish Origin checks. A violation fails the check and links to the bundle details. **Origin does not expose GitHub's requested-action buttons**, so it has no equivalent of the GitHub check's **Accept** action. Fix the size increase or change the threshold through Tuist's authorized project settings, then run CI again. Repository links open Origin; unsupported commit/source deep links remain plain text.

Only results for the current PR head, or a matching merge preview whose parents include that head, are published. Late results for a replaced commit do not get attached to the new head.

> [!IMPORTANT]
> **GitHub mirrors remain on GitHub CI.** Origin installations cannot write feedback to mirrored repositories, and Origin does not emit their CI push events. Keep the GitHub integration for those repositories. To use Origin-native CI, the repository must be hosted natively on Origin.

## Tuist-hosted runners {#tuist-hosted-runners}

Origin has no native workflow executor or runner registration API. **Buildkite orchestrates CI; Tuist provides Linux and macOS compute.** You need the Buildkite Origin repository-provider connection, your Tuist Buildkite runner connection, and Tuist's Origin App installed on the CI repository for checkout access. Installing Tuist's Origin App alone does not start builds.

1. Request access to Tuist Runners, which are currently invite-only.
2. In Buildkite, open **Settings → Repository Providers → Add Provider → Origin**. Install Buildkite's Origin app for the repository and create an Origin-backed pipeline. See [Buildkite's Origin guide](https://buildkite.com/docs/pipelines/source-control/origin).
3. Follow the <.localized_link href="/guides/features/runners/ci-providers/buildkite">Buildkite runner guide</.localized_link> to connect your cluster to Tuist and create a self-hosted queue matching a Tuist profile, such as `tuist-macos` or `tuist-linux`.
4. Create a <.localized_link href="/guides/server/authentication#continuous-integration">Tuist account token</.localized_link> with the **CI** preset, restricted to the reporting projects. Store it as a Buildkite secret and expose it to the job as `TUIST_TOKEN`. Tuist does not currently support Buildkite OIDC; the Origin app installation and runner-log credential do not authenticate CLI report uploads.
5. Target that queue from your pipeline:

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test and report"
       command: tuist test
       agents:
         queue: tuist-macos
   ```

Use a command suitable for your project's build system. Buildkite handles Origin push/PR triggers, checkout, workflow dependencies, cancellation and build checks. Tuist handles job dispatch, ephemeral runner isolation, logs, metrics and billing through its existing Buildkite integration.

Buildkite currently documents automatic Origin checkout credentials only for its own hosted agents. Tuist supplies checkout authentication separately: dispatch binds a signed grant to the account, job, installation and exact repository from Buildkite's protected job payload. The runner's Origin-only Git credential helper exchanges that grant for a fresh, read-only, single-repository installation token on each Git authentication. The app signing key stays on the server. A completed/cancelled job, suspended installation or removed repository cannot mint another token. The grant expires after twelve hours, matching the existing Buildkite job reporting limit.

Rebuild both runner images to install the helper and dispatch changes. The helper does not change GitHub SSH or other HTTPS checkout authentication, and it does not write tokens into Git remotes. CloneKit is optional and is not enabled by this integration.

## Configure an Origin App {#configure-an-origin-app}

For self-hosted servers or the initial hosted rollout, register an Origin App at [Origin app settings](https://cursor.com/codebase/settings/apps). Keep it private until the end-to-end installation and publishing flow is verified.

- Register the exact setup URL: `https://<your-tuist-host>/integrations/origin/setup`.
- Register the webhook URL: `https://<your-tuist-host>/webhooks/origin`. Tuist verifies Origin's Ed25519 signature over the raw delivery before queuing it. Installation lifecycle events are sent automatically; no push or PR event subscriptions are needed for Tuist reports, which are triggered by report uploads. Buildkite owns CI triggers through its separate installation.
- Request `repository:contents:read`, `repository:pull_requests:read`, `repository:pull_requests:reviews:write`, and `repository:checks:write`. Origin adds repository metadata access automatically. Contents access validates merge-preview ancestry.
- Generate an Ed25519 PKCS#8 private key and register **only its public key** with Origin. Store the app ID as `TUIST_ORIGIN_APP_ID` and the base64-encoded private PEM as `TUIST_ORIGIN_APP_PRIVATE_KEY_BASE64` in the server's secret manager. Restart the server after configuring them. Never commit either private key material or installation tokens.

Publishing is a separate external operation: [Origin's publishing guide](https://cursor.com/docs/origin/apps/publish) requires branding, a supported install/callback flow, least-privilege scopes and a demonstration of connecting, repository access changes, re-consent and uninstall. This implementation does not register, publish, or deploy an app automatically.

API contracts: [Origin API reference](https://cursor.com/docs/api/origin/llms-full.txt), [OpenAPI schema](https://cursor.com/docs/api/origin/openapi.yaml), and [Origin CI setup](https://cursor.com/docs/origin/clonekit-ci).
