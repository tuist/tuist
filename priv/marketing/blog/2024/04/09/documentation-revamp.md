---
title: "Revamping our documentation"
category: "product"
tags: ["tuist", "documentation", "guidelines"]
excerpt: "In this blog post, we share the journey we've been through to revamp the Tuist documentation and what we've learned."
author: pepicrft
---

One of the amazing things about open source is that anyone can contribute to a project and that means new and diverse perspectives can be brought to the table. However, that poses a challenge for maintainers: **how do you ensure that the project remains coherent and consistent when contributions come from so many different sources?** This challenge is not unique to code contributions, but also to documentation contributions. And this, unfortunately, is a challenge that we didn't handle well in the past. The result was a documentation that was inconsistent, outdated, and hard to navigate. But not anymore, since we've been working on revamping our documentation and we finally made it public at [docs.tuist.io](https://docs.tuist.io). In this update we'll share a bit about the journey we've been through and what we've learned.

## Documentation V1 - [Docusaurus](https://docusaurus.io/)

The first version of Tuist documentation was powered by [Docusaurus](https://docusaurus.io/), a NodeJS tool for generating static documentation satisfies. The framework provided us with all the tools necessary for creating a good documentation: a search engine, a sidebar, and a clean layout.

Moreover, we were quite strict about the **importance of updating the documentation as part of making contributions**. In other words, "I'll do it in a different" PR was not an option. This was a good practice that helped us keep the documentation up-to-date. However, that strictness faded away as the project grew and the number of contributors increased. The result was a documentation that was outdated and hard to navigate.

Because the tool required to set up the right version of [NodeJS](https://nodejs.org) in the environment, and have a bit of knowledge about the underlying technology *(e.g. installing dependencies with `npm` or running commands through `npm run`)* we started to ponder whether that'd feel as unnecessary friction for contributors. Around the same time that we were thinking about the contributors' friction, Apple released [Swift DocC](https://www.swift.org/documentation/docc/), a tool for generating documentation for Swift projects. We thought that it'd be a good opportunity to revamp the documentation and make it more accessible to contributors.

## Documentation V2 - [Swift DocC](https://www.swift.org/documentation/docc/)

As part of the effort to release [Tuist 4](/blog/2024/02/07/unveiling-tuist-4-and-tuist-cloud) we thought it'd be a good opportunity to revamp the documentation and make it more accessible to contributors. We decided to use [Swift DocC](https://www.swift.org/documentation/docc/) for generating the documentation. Many aspects of it read well in paper:

- It's writen in Swift
- It's tightly integrated into Xcode
- It can generate documentation from in-code documentation
- It's open source
- It has the notion of tutorials

However, the more we used it, the more we realized that it was not a good fit for our needs. In hindsight, we should have done a better research before making the decision, but we trusted the tool because it was developed by Apple. Here are some aspects that turned out to be not good for us:

- **The tool generates an actual SPA** using [Vue](https://vuejs.org/). Even though search engines are supposedly able to index SPAs, the indexing of Google degraded significantly having pages that were not indexed at all. Apple seems to be aware of the issue and they have plans to work on but it seems to be a low priority.
- **It has no support for i18n**. We want to set up a localization pipeline for our documentation site to ensure that languages are never a barrier for users and contributors. Sadly, Swift DocC doesn't have support for that. Not only that, but uses very proprietary formats that might complicate the integration with translation tools that expect more standard formats like [Markdown](https://en.wikipedia.org/wiki/Markdown).
- **Little extensibility and configurability:** Which means that you can't do things like generating content dynamically, customizing the `<head/>` section of the generated pages, customizing the routes, or changing the favicon. As a consequence, we had to have some scripts that worked directly with the output artifacts.

So while we were able to generate a documentation site that had the look-and-feel of Apple. We ended up with a tool that would limit us in the future. Moreover, we learned that the hesitance of contributors to update the documentation was not due to the tooling but rather to the lack of a culture of updating the documentation. In fact, with the introduction of Mise as a tool to manage the project's system dependencies, installing NodeJS and running `npm install` was not a big deal anymore.

Moreover, with the rush to release Tuist 4, we didn't have the time to properly organize the documentation and the content, so we end up in a terrible spot with content that was outdated, pages that were missing content, and a navigation that was hard to follow.

We decided to go back to the drawing board and think about what we wanted from the documentation.

## Documentation V3 - [VitePress](https://vitepress.dev/)

We had been following the amazing work the [Vue](https://vuejs.org/) ecosystem does with their tools. One of theme, [VitePress](https://vitepress.dev/), is a tool that they use to generate the documentation website for all their projects. It's aesthetically pleasing, it's extensible and configurable, it outputs a SSG site, it supports i18n, and it's actively maintained. It had everything we needed.

Like many times in the pass, we were confronted with the decision between choosing the right tool for the job, even if that meant choosing a technology stack other than Swift and Xcode, or sticking with the existing "official" options and trying to make them work. However, since we are limited in resources and getting involved in a project that's mainly steered by Apple would be a big commitment that would distract us from our main goal, we decided to go with VitePress.

It took us almost an entire week to go through all the versions of the documentation website pulling content from the old documentation, updating it, and organizing it. We also took the opportunity to add new content and improve the existing one. We also organized the content in the following sections for ease of navigation: Guides, Reference, Contributors, and Server.
The result of the work is already available under [docs.tuist.io](https://docs.tuist.io).

We have to admit that the experience working with VitePress has been top-notch. As an example of how powerful is extensibility is, we could use a tool like [SourceDocs](https://github.com/SourceDocs/SourceDocs) to turn in-code documentation into Markdown pages and dynamically load the content using VitePress built-in APIs for [data-loading](https://vitepress.dev/guide/data-loading).

## Preventing the same mistake

We made the mistake of being less strict about updating the documentation as part of making contributions. We learned that the tooling was not the problem, but rather the culture. Since we were limited in resources, it was a huge stretch for us to supervise documentation contributions on top of code contributions, our natural reaction was to ignored what it's indeed one of the most important parts of the project. We learned that we should have invested more time in creating a culture of updating the documentation as part of making contributions.

Going forward, **we'll require every PR to have documentation updates.** Since we have the priviledge of having people working full time on the project, we'll be able to supervise the contributions and ensure that the documentation is updated. We'll also be more strict about the quality of the documentation. We'll require that the documentation is clear, concise, and easy to follow. We might consider introducing some automation to ensure certain style guidelines are followed.

## Feedback

Give it a read and [let us know what you think](https://github.com/tuist/tuist/discussions/6160). We're always looking for ways to improve the documentation and make it more accessible to users and contributors. On behalf of the Tuist, we'd like to apologies for having disregarded the documentation for so long. We hope that the new documentation is a step in the right direction and that it helps you get started with Tuist.
