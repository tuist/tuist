---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub integration {#github}

Git repositories are the centerpiece of the vast majority of software projects out there. We integrate with GitHub to provide Tuist insights right in your pull requests and to save you some configuration such as syncing your default branch.

## Setup {#setup}

You will need to install the Tuist GitHub app in the `Integrations` tab of your organization:
![An image that shows the integrations tab](/images/guides/integrations/gitforge/github/integrations.png)

After that, you can add a project connection between your GitHub repository and your Tuist project:

![An image that shows adding the project connection](/images/guides/integrations/gitforge/github/add-project-connection.png)

> [!TIP]
> **Ip Allowlisting**
>
> If your GitHub organization uses [IP allow lists](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) or your GitHub instance is behind a firewall, make sure to allowlist Tuist's <.localized_link href="/guides/server/network#outbound-ip-addresses">outbound IP addresses</.localized_link> so that the integration can communicate with your repository.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist also integrates with self-hosted GitHub Enterprise Server (GHES) instances. In the GitHub integration card, switch to the **Enterprise server** tab, enter your GHES base URL (for example `https://github.example.com`), and click install.

Because GitHub Apps are scoped to a single GitHub instance, Tuist cannot reuse its github.com App on your GHES — instead, the install button takes you through GitHub's [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest): GHES walks your administrator through registering a fresh Tuist App on the instance, then hands the new App's credentials back to Tuist. Tuist stores those credentials encrypted per-installation and uses them for every API call, webhook signature, and link to your repositories from then on.

No additional Tuist server configuration is needed; the manifest flow generates and provisions everything automatically.

#### App permissions and webhook events {#github-app-permissions}

The GitHub Enterprise App manifest requests the following **repository permissions**:

| Permission | Access | Used for |
|---|---|---|
| Metadata (`metadata`) | Read-only | Basic repository metadata; required by GitHub for every App |
| Contents (`contents`) | Read-only | Reading repository contents |
| Pull requests (`pull_requests`) | Read and write | Accessing pull requests and supporting PR feedback |
| Issues (`issues`) | Read and write | Posting and updating PR comments through GitHub's issue comments API |
| Checks (`checks`) | Read and write | Creating and updating check runs, including bundle-size pass/fail checks |

The App subscribes to the `check_run`, `pull_request`, and `issue_comment` webhook events. The manifest flow configures these permissions and subscriptions automatically.

For manual App setup on github.com with a self-hosted Tuist server, see <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">the self-hosting guide</.localized_link>.

#### Separate browser and API URLs {#separate-browser-and-api-urls}

If engineers access GitHub Enterprise through an internal hostname while third-party services use an external proxy, configure both addresses before clicking install:

| Field | Example | Used by |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | Your browser, for App registration and installation, and links to GitHub from Tuist |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist's servers, for the manifest-code exchange, access tokens, repository access, PR comments, and checks |

The API URL is the full REST API base URL, including `/api/v3` or the equivalent path exposed by your proxy. Tuist does not append `/api/v3` to an explicit API URL. Leave it empty if one hostname works for both your browser and Tuist; existing connections keep using `<Server URL>/api/v3`.

Both addresses must route to the **same GitHub Enterprise instance**. Your browser only needs to reach the Server URL, not the API proxy. Tuist's servers only need to reach the API URL, not the internal browser hostname.

For the external proxy:

- Use HTTPS with a certificate trusted by Tuist's servers and public DNS resolving to public IP addresses. API URL overrides do not bypass Tuist's private-IP/SSRF protections. The override must target your Enterprise instance, not `github.com` or a `*.github.com` endpoint.
- Allowlist every Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">outbound IP address</.localized_link>.
- Forward the REST API endpoints Tuist uses, including `POST /api/v3/app-manifests/{code}/conversions`, `POST /api/v3/app/installations/{installation_id}/access_tokens`, and repository API endpoints for comments and checks. These are GitHub's upstream paths; translate them if your proxy exposes a different prefix.
- Forward requests to GitHub without HTTP redirects or an interactive sign-in page. Tuist does not automatically follow Enterprise API redirects, so they cannot bypass public-IP checks. The manifest conversion endpoint must be reachable during setup, before Tuist has the App's credentials. GitHub Actions log downloads are an exception: Tuist follows signed archive redirects only over HTTPS, checks and pins every destination to a public IP, and does not forward the installation token.

GitHub may return pagination links using its internal hostname. Tuist rebases links from the configured GitHub instance onto the API URL, preserving your proxy's path prefix; links to unrelated origins are rejected.

Separately, GitHub must be able to deliver webhooks to `https://tuist.dev/webhooks/github` (or `/webhooks/github` on your self-hosted Tuist server). Engineers must be able to return to Tuist to complete the browser callbacks. The API URL does not change either destination.

Organization administrators can also change or clear the API URL on an existing Enterprise integration using **Save API URL** in the integration card. No App reinstallation or project reconnection is needed. Clearing it restores `<Server URL>/api/v3`. Saving validates the URL format, not proxy connectivity. Webhook processing may take up to one minute to use a changed address because installation lookups are cached; requests already in flight may still use the previous address.

> [!NOTE]
> **Enterprise plan only on the hosted Tuist server**
>
> On the hosted Tuist server (`https://tuist.dev`), the GitHub Enterprise Server integration is available exclusively to organizations on the **Enterprise** plan. Self-hosted Tuist deployments can use it on any plan.

## Pull/merge request comments {#pull-merge-request-comments}

The GitHub app posts a Tuist run report, which includes a summary of the PR, including links to the latest <.localized_link href="/guides/features/previews#pullmerge-request-comments">previews</.localized_link> or <.localized_link href="/guides/features/selective-testing#pullmerge-request-comments">tests</.localized_link>:

![An image that shows the pull request comment](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **Requirements**
>
> The comment is only posted when your CI runs are <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>.

> [!NOTE]
> **Github_ref**
>
> If you have a custom workflow that's not triggered on a PR commit, but for example, a GitHub comment, you might need to ensure that the `GITHUB_REF` variable is set to either `refs/pull/<PR_NUMBER>/merge` or `refs/pull/<PR_NUMBER>/head`.
>
> You can run the relevant command, like `tuist share`, with the prefixed `GITHUB_REF` environment variable: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions job summary {#github-actions-job-summary}

When you run Tuist in GitHub Actions, it writes a run report to the [job summary](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/) of the workflow run, so you see your test and build results on the run's summary page with nothing extra to set up. The summary links to the full report on Tuist, where richer insights such as flaky tests and bundle-size deltas are available.

![An image that shows the Tuist run report in the GitHub Actions job summary](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

This is particularly useful with [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue). A merge queue run is not attached to a pull request, so no comment is posted, but the job summary still surfaces the results.

> [!NOTE]
> **Requirements**
>
> Like the pull/merge request comment, the job summary is only written when your CI runs are <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>.

