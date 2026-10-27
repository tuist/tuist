---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Publish Tuist build, test, bundle, and preview insights on Entire Trails."
}
---
# Entire integration {#entire}

Tuist maintains a summary discussion on each connected repository's open or draft [Trail](https://docs.entire.com/guides/trails/overview). The summary includes available build results, test failures and flaky tests, bundle sizes, and app previews, with links to the full reports on Tuist.

> [!IMPORTANT]
> **Early access**
>
> Entire plugins require partner registration, and its Trail discussions and webhook contracts are experimental. This integration is opt-in and must be enabled for your account by your Tuist administrator.

## Setup {#setup}

The installation follows the same flow as the GitHub integration: install the plugin for your account, then connect repositories to Tuist projects. On hosted Tuist, your administrator handles plugin registration and server configuration; you only need the steps below.

1. Open your account's **Settings → Integrations**.
2. In **Entire**, select **Install Entire plugin**. Choose the Entire project and repositories you want to share with Tuist.

   ![Install the Entire plugin from account integrations](/images/guides/integrations/gitforge/entire/integrations.png)

3. Back in Tuist, select **Add new project connection**. In **Choose repository to connect to**, choose your Tuist project and Entire repository, then select **Create Connection**. If only one Tuist project is available, it is selected automatically.

   ![Connect a Tuist project to an Entire repository](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. Keep uploading your insights from CI using your existing authenticated Tuist commands. Tuist matches them to each Trail's current commit SHA; no Entire-specific CLI flags are needed.

A Tuist project can retain its GitHub connection while also publishing summaries to Entire. This is useful for GitHub mirrors. Trail summaries do not require Tuist's CI executor or change your existing CI provider.

Tuist updates the same discussion as insights arrive. Opening or reopening a Trail also picks up previously uploaded insights for its head commit. Closed and merged Trails are not updated. Results from older commits are never presented as results for the current head. If no insights exist for the current commit, Tuist leaves any existing summary unchanged; each result includes its commit hash.

To remove a project connection, open its **Manage** menu and select **Remove connection**, just as with GitHub. This stops future updates and deletes Tuist's local discussion pointers. Comments already published remain on Entire. Reconnecting recovers the existing summary when it is still accessible. To change the plugin's repository access or uninstall it, use the project's **Plugins** settings in Entire.

## Server configuration {#server-configuration}

This section is for Tuist server operators. Register the plugin with Entire using the [plugin registration guide](https://docs.entire.com/guides/api/plugins/register). Request `contents:read` and `discussions:write`. The read permission is needed for Trail events and discussion discovery; repository write access is not required.

Configure these server environment variables:

| Variable | Purpose |
| --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | Slug confirmed by Entire |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | Ed25519 private key in PEM format, supplied through your secret store |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | Key ID when using JWKS-based key registration; otherwise optional |
| `TUIST_ENTIRE_CORE_URL` | Entire Core used for installation requests; defaults to `https://eu.auth.entire.io` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | Webhook signing-key URL supplied by Entire at registration |

Register `https://<your-tuist-host>/integrations/entire/callback` as the post-install URL and `https://<your-tuist-host>/webhooks/entire` as the webhook URL. Enable the `entire_trails` feature flag for the account after applying the server migrations. Entire Trail summaries are independent of Tuist's CI execution configuration and feature flag.

Tuist verifies installation receipts and webhook signatures, mints short-lived repository-scoped tokens, and discovers each repository's current processing region before publishing. Tokens are never embedded in report links.
