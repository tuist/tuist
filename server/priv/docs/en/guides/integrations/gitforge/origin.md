---
{
  "title": "Origin",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Connect native Cursor Origin repositories to Tuist pull request reports."
}
---
# Origin integration {#origin}

Tuist can post build, test, preview, and bundle reports on pull requests in native [Cursor Origin](https://cursor.com/docs/api/origin) repositories. It updates the app's existing Tuist Run Report instead of posting a new comment for every upload.

Installing the app does not run builds or tests. Your existing workflows continue uploading results to Tuist, and the integration brings those results into your pull requests.

## Setup {#setup}

An administrator of the Tuist account should open **Settings → Integrations**, choose **Install Origin App** in the Origin card, and approve access in Cursor. Choose the Origin account or namespace and repositories that Tuist should access, then return to Tuist. The connection belongs to the Tuist account, not an individual project.

You can also install the app directly from Origin. After approving access, log in to Tuist if needed and choose the organization to connect. Only organizations you administer and your personal account are available. If only one account is available, Tuist connects it automatically without showing the chooser. If you start from Tuist, the organization is already selected and this step is skipped.

Choose **Add new project connection** to open the repository selection modal. Select an unconnected Tuist project and one of the repositories discovered from the connected Origin account, then choose **Create Connection**. If multiple Origin accounts are connected, choose the account first. Only native Origin repositories are available for connection. Tuist verifies pull-request access again before connecting the project and adopts the repository's default branch.

Use **Manage integration** to open Cursor's consent flow in a new tab and adjust repository access or connect another Origin account. Repository-loading failures show **Retry**, separate from a successful empty repository list.

Use an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> to authenticate result uploads.

## Reports and permissions {#reports-and-permissions}

When approving the app, you grant the permissions needed to connect repositories and publish reports:

| Permission | Used for |
| --- | --- |
| Pull requests: read | Find the open pull request for the reported commit. |
| Pull request reviews: read and write | Read, post, and update the Tuist Run Report comment. |
| Repository metadata: read | Discover repositories and their default branches. Included automatically by Origin. |

Tuist does not need access to your source code or permission to merge pull requests.

To associate results with a pull request, uploads must include the repository's Origin clone URL, Git ref, and full commit SHA. Tuist posts the report only when those identify a single open pull request at its current head commit. Results for superseded commits do not overwrite the current report.

The Origin card lists project-to-repository connections. Choose **Manage → Remove connection** on a project connection to stop its reporting without uninstalling the app. Uninstall the app in Cursor to revoke its access; Tuist removes the installation and its project connections when it processes the installation notification.

## Self-hosted servers {#server-configuration}

If you host your own Tuist server, register and configure an Origin app for your deployment first. Follow the <.localized_link href="/guides/server/self-host/server#platform-origin">Origin self-hosting instructions</.localized_link>, then return to the setup steps above to connect accounts and projects.
