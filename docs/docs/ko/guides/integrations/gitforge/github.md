---
title: GitHub titleTemplate: :title | Git forges | Integrations | Guides | Tuist
description: Learn how to integrate Tuist with GitHub for enhanced workflows.
---

# GitHub integration {#github}

Git repositories are the centerpiece of the vast majority of software projects
out there. We integrate with GitHub to provide Tuist insights right in your pull
requests and to save you some configuration such as syncing your default branch.

## Setup {#setup}

Install the [Tuist GitHub app](https://github.com/marketplace/tuist). Once
installed, you will need to tell Tuist the URL of your repository, such as:

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
