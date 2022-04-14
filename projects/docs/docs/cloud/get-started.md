---
title: Get started
slug: '/cloud/get-started'
description: 'Learn how to set up Tuist Cloud on your projects to have access to new workflows and integrations.'
---

:::caution Work in progress
[Tuist Cloud](https://cloud.tuist.io) is currently in alpha and we don't make any assurances about the stability of the feature.
If you feel adventurous and would like to be early adopter and feedback provider, 
you'll find up-to-date documentation here.  
:::

## Motivation

Before we dive into how to set up a project on **Tuist Cloud** we must understand what the tool is in the first place.
While developing Tuist,
we realized **workflows** and **integrations** that we could only enable through a server component.
A server allows storing state in a shared database,
has an [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) that other services can reach through webhooks,
and can perform periodic tasks through jobs.
A server would open the door to new practical workflows that would significantly **improve the experience of scaling up Xcode projects and collaborating** when building apps.

Moreover,
we were looking for ways to make the project sustainable long-term.
Many open-source projects fail to achieve that, 
and they end up either abandoned or burning out the maintainers.
[GitHub Sponsors](https://github.com/sponsors/tuist) help cover some costs and contributions help keep the project moving.
Still, we believe the project would greatly benefit from working on it full-time, 
devising the direction,
implementing new features,
and providing continuous support.
What if **Tuist Cloud** is the solution?
That's what we are aiming to achieve, 
taking inspiration from tools like [Plausible](https://plausible.io/) and [Ghost](https://ghost.org/).

The project is an [open-source](https://github.com/tuist/tuist/tree/main/projects/cloud) Rails app licensed under MIT.
Teams can self-host it themselves.
However, 
we document the process to self-host the project and design it for easy hosting.
We **recommend** the usage of the Tuist-hosted solution.
It provides benefits like support, monitoring, and continuous updates,
and you support a project your project depends on.
You can also take the adventurous path of building your backend.
The [specification](cloud/specification.md) documents the contract and designs it to be platform-agnostic.

## Usage

To set up Tuist Cloud, you will first need to sign up at [cloud.tuist.io](https://cloud.tuist.io) and create a project. You can also create an organization if you intend to work in a team. Once created, you can invite your team members to the organization.

For remote cache, you will also need to set up an [S3 bucket](https://aws.amazon.com/s3/) and provide Tuist Cloud with your [access key](https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html). The access key needs write and read permissions for the bucket you plan to use with Tuist Cloud. We also plan to offer more providers in the future.

In your project, you then need to add a reference to Tuist Cloud in your `Config.swift`:
```
import ProjectDescription

let config = Config(
    cloud: .cloud(projectId: "your-organization/your-project", url: "https://cloud.tuist.io", options: [.optional])
)
```

Afterwards, you can simply run `tuist cloud auth` - and that's it 🎉  When you then run `tuist generate App`, all available binaries will be automatically downloaded from remote if available. You can also warm all the targets with `tuist cache warm`. At the end of the command, all the binaries will be uploaded to your S3 bucket.

If you ever need to remove your Tuist Cloud credentials on your machine, you can run `tuist cloud logout`.

### CI

One of the great benefits of Tuist Cloud is that you can cache your targets on CI. Obtain your project token from the `Remote cache` page in Tuist Cloud and you can add a step in your CI pipeline configuration for warming all the targets by `TUIST_CONFIG_CLOUD_TOKEN="token-from-tuist-cloud" tuist cache warm`.
