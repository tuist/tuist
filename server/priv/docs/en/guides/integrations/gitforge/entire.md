---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Publish Tuist build, test, bundle, and preview insights on Entire Trails."
}
---
# Entire integration {#entire}

Tuist can publish build, test, preview, and bundle insights on open and draft [Trails](https://docs.entire.com/guides/trails/overview) in [Entire](https://entire.com) repositories. Each Trail gets a Tuist gate with the run report, whole-change findings for failed and flaky tests, and a summary comment that Tuist updates as new insights arrive instead of posting a new one for every upload.

Installing the plugin does not run builds or tests. Your existing workflows continue uploading results to Tuist, and the integration brings those results into your Trails.

## Setup {#setup}

An administrator of the Tuist account installs the plugin, then connects repositories to Tuist projects, as with the <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> and <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> integrations.

1. Open your account's **Settings → Integrations**.
2. In the Entire card, choose **Install Entire plugin**. Choose the Entire project and repositories you want to share with Tuist.

   ![Install the Entire plugin from account integrations](/images/guides/integrations/gitforge/entire/integrations.png)

3. Back in Tuist, choose **Add new project connection**. In **Choose repository to connect to**, select your Tuist project and Entire repository, then choose **Create Connection**. If only one Tuist project is available, it is selected automatically.

   ![Connect a Tuist project to an Entire repository](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. Keep uploading results from CI with your existing, authenticated Tuist commands, for example using an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>. Tuist matches results to each Trail's current head commit, so no Entire-specific flags are needed.

A Tuist project can keep its GitHub connection while also publishing to Entire, which is useful when the Entire repository mirrors a GitHub repository. The integration does not require Tuist's CI executor or change your CI provider.

## Reports and permissions {#reports-and-permissions}

When installing the plugin, you grant the permissions it needs to find Trails and publish reports:

| Permission | Used for |
| --- | --- |
| Repository contents: read | Receive Trail events and find open and draft Trails with their head commits. |
| Checks: write | Publish the Tuist gate on the Trail's head commit. |
| Findings: write | Publish failed and flaky tests as findings, and resolve findings a newer report replaces. |
| Discussions: write | Post and update the summary comment. Without it, Tuist still publishes the gate and findings. |

Tuist does not need write access to your source code or permission to merge Trails.

Tuist publishes three things on each Trail:

- **Gate:** the Tuist check appears under **Gates** with the run report and a link to the project on Tuist. It is listed under the Tuist plugin, separately from a GitHub mirror's **Checks** gate. It completes with a `neutral` conclusion, which Entire shows as passed, because uploaded results do not tell Tuist whether every expected CI job has finished. It does not block merging, even when there are findings, so keep your CI provider's required checks for pass/fail enforcement.
- **Findings:** failed tests and flaky tests appear as whole-change findings that link to the test cases on Tuist. Findings do not contribute to Entire's Agent review gate.
- **Summary comment:** like the pull request comment on GitHub and Origin, each project keeps one Tuist Run Report comment per Trail. If you delete it, the next report posts it again.

As new results arrive, Tuist publishes an updated report for the Trail's current head commit and resolves the findings it replaces. Retries do not create duplicate reviews, findings, or comments, including when Entire's response to a publication is lost. Opening or reopening a Trail picks up results already uploaded for its head commit. If no results exist for the current head commit, Tuist publishes nothing new, so an older commit's gate cannot satisfy requirements for the new head. Closed and merged Trails are not updated.

The Entire card lists project-to-repository connections. Choose **Manage → Remove connection** on a project connection to stop its reporting without uninstalling the plugin. Reports already published remain on Entire, and reconnecting starts new reports. To change the plugin's repository access or uninstall it, use the project's **Plugins** settings in Entire.

## Self-hosted servers {#server-configuration}

If you host your own Tuist server, register and configure an Entire plugin for your deployment first. Follow the <.localized_link href="/guides/server/self-host/server#platform-entire">Entire self-hosting instructions</.localized_link>, then return to the setup steps above to connect accounts and projects.
