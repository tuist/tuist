---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Publish Tuist build, test, bundle, and preview insights on Entire Trails."
}
---
# Entire integration {#entire}

Tuist publishes an informational Check, a Findings review, and a summary comment on each connected repository's open or draft [Trail](https://docs.entire.com/guides/trails/overview). The report includes available build results, test failures and flaky tests, bundle sizes, and app previews, with links to the full reports on Tuist. Failed tests and flaky tests appear as whole-change findings, rather than speculative line-level diagnoses. Like the GitHub integration's pull request comment, each project keeps one summary comment per Trail and edits it as new insights arrive.

> [!IMPORTANT]
> **Early access**
>
> Entire plugins require partner registration, and its Findings and webhook contracts are experimental. Your Tuist administrator can enable the integration for all accounts or selected accounts. Your Entire project must also be allowed to install the registered plugin.

## Setup {#setup}

The installation follows the same flow as the GitHub integration: install the plugin for your account, then connect repositories to Tuist projects. On hosted Tuist, your administrator handles plugin registration and server configuration; you only need the steps below.

1. Open your account's **Settings → Integrations**.
2. In **Entire**, select **Install Entire plugin**. Choose the Entire project and repositories you want to share with Tuist.

   ![Install the Entire plugin from account integrations](/images/guides/integrations/gitforge/entire/integrations.png)

3. Back in Tuist, select **Add new project connection**. In **Choose repository to connect to**, choose your Tuist project and Entire repository, then select **Create Connection**. If only one Tuist project is available, it is selected automatically.

   ![Connect a Tuist project to an Entire repository](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. Keep uploading your insights from CI using your existing authenticated Tuist commands. Tuist matches them to each Trail's current commit SHA; no Entire-specific CLI flags are needed.

A Tuist project can retain its GitHub connection while also publishing summaries to Entire. This is useful for GitHub mirrors. Trail summaries do not require Tuist's CI executor or change your existing CI provider.

Tuist publishes a new report attempt as insights arrive, pinning its review to the analyzed head commit and resolving findings superseded by the updated report. Unchanged retries reuse the same attempt and do not create duplicate reviews, findings, or comments. If you delete the summary comment, the next report posts it again. If a publication response is lost, Tuist recovers the started attempt before replacing it, even after the head advances or before the new head has insights. Recovered results remain pinned to the analyzed commit. Opening or reopening a Trail also picks up previously uploaded insights for its head commit. Closed and merged Trails are not updated. If no insights exist for the current commit, Tuist starts no new report; an older commit's Check cannot satisfy requirements for the new head.

The Check appears in the Tuist plugin's gate under **Gates**, not the GitHub mirror's separate **Checks** gate. It completes with a `neutral` conclusion: this integration reports uploaded observations and does not know whether every expected CI job has finished. It does not block merging, even when the report contains findings. Keep your CI provider's required checks for pass/fail enforcement. Findings do not contribute to Entire's Agent review gate.

To remove a project connection, open its **Manage** menu and select **Remove connection**, just as with GitHub. This stops future updates and deletes Tuist's local report snapshot and publication pointers. Reports already published remain on Entire. Reconnecting starts new report attempts. To change the plugin's repository access or uninstall it, use the project's **Plugins** settings in Entire.

## Server configuration {#server-configuration}

This section is for Tuist server operators. Register the plugin with Entire using the [plugin registration guide](https://docs.entire.com/guides/api/plugins/register). Request `contents:read`, `checks:write`, `findings:write`, and `discussions:write`. The read permission is needed for Trail events and discovery, and `discussions:write` for the summary comment; repository write access is not required. Installations that have not granted `discussions:write` still receive the Check and Findings, without the comment. For existing registrations, ask Entire to add the new permissions and confirm that installations grant them before enabling this version. Apply the server migrations before rolling out the application. See Entire's [Checks](https://docs.entire.com/guides/api/plugins/report-checks), [Findings](https://docs.entire.com/guides/api/plugins/trail-findings), and [Trail comments](https://docs.entire.com/guides/api/plugins/trail-comments.md) contracts.

Report state, including the summary comment's discussion and message IDs, uses the separate `entire_trail_reports` table. The legacy discussion table and its required pointers stay unchanged, so older replicas never read rows from the new table. For application rollback, leave the reports table in place so a later upgrade can recover unfinished attempts. Roll back its migration only after stopping all Checks/Findings publishers and deliberately accepting the loss of their local recovery state; legacy discussion pointers are unaffected.

Configure these server environment variables:

| Variable | Purpose |
| --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | Slug confirmed by Entire |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | Ed25519 private key in PEM format, supplied through your secret store |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | Key ID when using JWKS-based key registration; otherwise optional |
| `TUIST_ENTIRE_CORE_URL` | Entire Core used for installation requests; defaults to `https://eu.auth.entire.io` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | Webhook signing-key URL supplied by Entire at registration |

For managed Helm deployments, store the private PEM in the environment's 1Password vault as `ENTIRE_PLUGIN/private_key`, then enable `server.config.entirePluginKey.enabled` alongside `server.config.managedSecrets`. External Secrets supplies `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` through the existing server-config Secret without trimming the multiline PEM. The item and field names are configurable through `server.config.entirePluginKey.item` and `.field`. This mapping defaults off and does not configure the slug or webhook signing-key URL; supply those separately after registration. Each environment should use its own signing key. Share only the public PEM with Entire, never the private key.

Register `https://<your-tuist-host>/integrations/entire/callback` as the post-install URL and `https://<your-tuist-host>/webhooks/entire` as the webhook URL. After applying the server migrations, enable the `entire_trails` feature flag globally to offer the integration to all accounts, or enable it for selected accounts. For a public rollout, ask your Entire contact to allow installation outside the plugin's owning project; enabling the Tuist feature flag does not change Entire's installation policy. Entire Trail summaries are independent of Tuist's CI execution configuration and feature flag.

Tuist verifies installation receipts and webhook signatures, mints short-lived repository-scoped tokens, and discovers each repository's current processing region before publishing. Tokens are never embedded in report links.
