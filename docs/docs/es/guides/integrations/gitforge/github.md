---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to connect Tuist to other tools and services."
}
---
# Integrations {#integrations}

We strongly believe we should meet developers where they are, and let's be honest, developers spend time outside of their coding environments, such as reviewing pull request on [GitHub](https://github.com) or communicating with their team on [Slack](https://slack.com). That's why we've built integrations with popular tools and services to make it easier for you to use Tuist in your workflows. This page lists the integrations we currently support.

## Git platforms {#git-platforms}

Git repositories are the centerpiece of the vast majority of software projects out there. We integrate with your Git platform to provide Tuist insights right in your pull requests or to save you some configuration such as syncing your default branch.

### GitHub {#github}

Install the [Tuist GitHub app](https://github.com/marketplace/tuist). Once installed, you will need to tell Tuist the URL of your repository, such as:

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
