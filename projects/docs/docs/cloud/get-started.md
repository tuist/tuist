---
title: Get started
slug: '/cloud/get-started'
description: 'Learn how to set up Tuist Cloud on your projects to have access to new workflows and integrations.'
---

:::caution Work in progress
[Tuist Cloud](https://github.com/tuist/cloud) is under development and therefore we don't recommend its usage yet.
If you feel adventurous and would like to be early adopter and feedback provider, 
you'll find up-to-date documentation here.  
:::

## Motivation

Before we dive into how to set up a project on **Tuist Cloud** it's important that we understand what the tool is in the first place.
While developing Tuist,
we realized there were **workflows** and **integrations** that we could only enable through a server component.
A server allows storing state in a shared database,
has a [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) that other services can reach through webhooks,
and can perform periodic tasks through jobs.
A server would open the door to new useful workflows that would significantly **improve the experience of scaling up Xcode projects and collaborating** when building apps.

Moreover,
we were looking for ways to make the project sustainable long-term.
Many open-source projects fail are achieving that and they end up either abandoned or burning out the maintainers.
[GitHub Sponsors](https://github.com/sponsors/tuist) helps cover some costs, an contributions keep the project moving,
but we believe the project would greatly benefit from having people working on it full-time devising the direction,
implementing new features,
and providing continuous support.
What if **Tuist Cloud** is the solution?
That's what we are aiming to achieve taking inspiration from tools like [Plausible](https://plausible.io/) and [Ghost](https://ghost.org/).

The project is an [open-source](https://github.com/tuist/cloud) Rails app licensed under AGPL-3.0.
Teams can self-host it themselves.
Although we document the process to self-host the project and design it to for easy hosting.
we **recommend** the usage of the Tuist-hosted solution.
It provides benefits like support, monitoring, and continuous updates,
and you support a project your project depends on.
You can also take the adventurous path of building your own backend.
The [specification](/cloud/specification) documents the contract and design it to be platform-agnostic.

:::info APGPL-3.0
Note that the AGPL-3.0 license under which Tuist Cloud is licensed allows you to host the code yourself, but modifications of the project need to be contributed upstream.
:::