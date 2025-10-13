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

## Pull/merge request comments {#pull-merge-request-comments}

The GitHub app posts a Tuist run report, which includes a summary of the PR, including links to the latest <LocalizedLink href="/guides/features/previews#pullmerge-request-comments">previews</LocalizedLink> or <LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">tests</LocalizedLink>:

![An image that shows the pull request comment](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
The comment is only posted when your CI runs are <LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
If you have a custom workflow that's not triggered on a PR commit, but for example, a GitHub comment, you might need to ensure that the `GITHUB_REF` variable is set to either `refs/pull/<PR_NUMBER>/merge` or `refs/pull/<PR_NUMBER>/head`.

You can run the relevant command, like `tuist share`, with the prefixed `GITHUB_REF` environment variable: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
