---
{
  "title": "Origin",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Connect native Cursor Origin repositories to Tuist pull request reports."
}
---
# Origin integration {#origin}

Tuist can post build, test, preview, and bundle reports on pull requests in native [Cursor Origin](https://cursor.com/docs/api/origin) repositories. It updates the app's existing Tuist Run Report instead of posting a new comment for every upload.

This is a Git forge integration, not Cursor Cloud Agent compute or the Cursor plugin/MCP marketplace. Installing the app does not run CI or upload results. Your existing CI or local workflow must report results to Tuist.

## Setup {#setup}

An administrator of the Tuist account should open **Settings → Integrations**, choose **Connect** in the Origin card, and approve access in Cursor. Choose the Origin account or namespace and repositories that Tuist should access, then return to Tuist. The connection belongs to the Tuist account, not an individual project.

Choose **Add new project connection** to open the repository selection modal. Select an unconnected Tuist project and one of the repositories discovered from the connected Origin account, then choose **Create Connection**. If multiple Origin accounts are connected, choose the account first. Known GitHub mirrors are excluded from the repository choices. Tuist verifies native pull-request access again before connecting the project and adopts the repository's default branch.

Use **Manage integration** to open Cursor's consent flow in a new tab and adjust repository access or connect another Origin account. Repository-loading failures show **Retry**, separate from a successful empty repository list.

Use an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> to authenticate result uploads. The Origin integration does not enable GitHub OIDC authentication.

GitHub mirrors must use the <.localized_link href="/guides/integrations/gitforge/github">GitHub integration</.localized_link>. Origin installation tokens cannot comment on mirrored pull requests.

## Reports and permissions {#reports-and-permissions}

The app requests these scopes:

- `repository:pull_requests:read`
- `repository:pull_requests:reviews:write`, which includes the corresponding review-read permission

Repository metadata access is granted automatically during installation. Tuist explicitly includes `repository:metadata:read` when minting narrowed installation tokens so it can read the repository metadata required for project linking. Tuist does not need code access, merge permissions, check-run permissions, or user delegation for comments.

Report uploads must include the Origin clone URL, Git ref, and full commit SHA. Both current clone URL forms are recognized: `https://origin.cursor.com/owner/repository.git` and the legacy `https://origin.cursor.com/git/owner/repository.git`. A branch ref or `refs/pull/<number>/...` must resolve to a single open pull request whose current head SHA matches the uploaded commit. Reports for superseded commits are skipped. Commit SHAs and failure locations are shown as code in Origin comments rather than constructing unverified GitHub-style browser links; links to Tuist reports and previews remain available.

Removing a project connection stops its reporting. **Disconnect** removes the installation's Tuist-side association and its project connections; it does not uninstall the app in Cursor. Uninstall the app in Cursor to revoke its access there.

## Server configuration {#server-configuration}

Origin installation is available when the deployment has both `TUIST_ORIGIN_APP_ID` and `TUIST_ORIGIN_APP_PRIVATE_KEY`. In development, the card remains visible with setup guidance and a disabled **Connect** button until both are configured. The private key is an Ed25519 PKCS#8 PEM whose public key is registered with that Origin app. Never commit or share the private key. Use independent apps and keys for each environment.

Register these HTTPS URLs for the deployment:

- Installation callback: `<Tuist base URL>/integrations/origin/setup`
- Webhook: `<Tuist base URL>/webhooks/origin`

Optional repository webhook events are not needed for comments. Tuist accepts installation lifecycle notifications, verifies Cursor's signatures, and queues reconciliation durably. Installation receipts are verified against Cursor's public signing keys and browser-bound consent state, not against the app's private key.

Managed deployments load `ORIGIN_APP/app_id` and `ORIGIN_APP/private_key` together from their environment's 1Password vault when `server.config.originAppKey.enabled` is enabled.

For local development, `server/fnox.toml` loads `Development/ORIGIN_APP/app_id` and `Development/ORIGIN_APP/private_key`. Use an HTTPS tunnel matching the registered callback and Tuist base URL. Apply the Origin database migration before testing installation and project linking.
