---
title: Why a server?
titleTemplate: :title | Introduction | Server | Tuist
description: Learn why Tuist has a server and how it can help scale your app development.
---

# Why a server?

At a certain scale, optimizing a project and developers' interactions with them require access to data that changes over time, and integrations with other internet services where teams collaborate. This is only possible with **a server that can store data in a database, process it asynchonously, and integrate it with other services.**

While the role of a server is common in other ecosystems, it's not that common in app development. Teams leaned heavily on open source solutions that leveraged the capabilities of CI services to approximate the capabilities of a server. However, as the complexity of the projects and the number of developers working on them increased, the limitations of these solutions became more evident.

We believe teams shouldn't have to worry about setting up and maintaining a server to scale their projects. That's why we built a server that [Tuist](/en/guides/develop/projects) and [Xcode projects](https://developer.apple.com/documentation/xcode/creating-an-xcode-project-for-an-app) can integrate with to scale their projects and teams.

> [!TIP] GIVING YOUR PROJECTS AND WORKFLOWS SUPERPOWERS
> A way of thinking about the server is as a superpower that you can give to your projects and workflows.
> Some superpowers like [binary caching](/en/guides/develop/build/cache) require you to have a [Tuist project](/en/guides/develop/projects) but others just work with vanilla Xcode projects.
