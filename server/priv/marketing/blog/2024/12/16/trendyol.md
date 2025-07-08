---
title: "Enabling Tuist Cache: Enhancing the Developer Experience at Trendyol"
category: "case-studies"
tags: ["cache", "test-selection", "developer-experience", "tests"]
excerpt: "Trendyol reduced build times by 65% with Tuist, cutting CI builds to 10 minutes and local UI test setups to 30 seconds. Their self-hosted Tuist instance ensures secure, fast performance, streamlining workflows for 170+ developers."
author: aatakankarsli
og_image_path: /marketing/images/blog/2024/12/16/trendyol/og.jpg
highlighted: true
---

At [Trendyol](https://www.trendyol.com), our journey with Tuist began as outlined in our previous article, [Trendyol and Tuist: Engineering Apps at Scale](https://tuist.dev/blog/2023/09/08/trendyol-and-tuist). There, we discussed how Tuist helped us organize our large and complex project structures across multiple teams and domains. Building on that foundation, we recently [introduced selective unit testing](https://medium.com/trendyol-tech/selective-unit-testing-on-ios-achieve-80-faster-feedback-42e865c8ce20) to accelerate our feedback loop by up to 80%. However, even with these test-execution improvements, both local and CI builds continued to stretch beyond 30 minutes, affecting the pace at which developers could iterate.

As Turkey’s leading e-commerce platform and a super-app serving more than 10 domain teams and 170+ developers across iOS and Android, speed at scale is supreme. To further optimize our workflows, we took the next logical step: leveraging tuist cache to improve build times and deliver a better overall developer experience

## Why [Tuist Cache](https://docs.tuist.dev/en/guides/develop/build/cache)?

Originally, our motivation with the Tuist was to enable caching for local development. Although CI speed matters, it’s the local feedback loops that directly influence a developer’s ability to experiment quickly. Once we began using the [Tuist Server](https://docs.tuist.dev/en/server/introduction/why-a-server), we saw immediate benefits. With effective caching, Xcode no longer needed to spend significant time indexing files, making the IDE feel noticeably more responsive. Builds became faster, and the everyday frustration of waiting on incremental builds greatly decreased.

<img style="max-width: 600px" src="/marketing/images/blog/2024/12/16/trendyol/build-duration-graph.webp" alt="Build Time Graph for Trendyol iOS App"/>


## Combining [selective testing](https://docs.tuist.dev/en/guides/develop/test/smart-runner) with Tuist Cache

After speeding up compilation, we turned our attention to tests, which we could further optimize by running them selectively. At the time we started exploring this, Tuist had not yet shipped [selective testing](https://docs.tuist.dev/en/guides/develop/test/smart-runner), so we built a plugin leveraging `git diff` and `tuist graph` to identify only the modules affected by code changes. This allowed us to run a more focused set of unit and UI tests.  

Integrating selective testing with binary caching can be a game-changer. Here’s how the two work together:  

1. **Change detection:** We identify which files and modules were changed since the last build.  
2. **Targeted caching:** Modules not impacted by the recent changes are retrieved from the Tuist cache. Instead of rebuilding everything, these modules reuse cached outputs.  
3. **Significant time savings:** After a month-long proof of concept, our build times were reduced by 65%. In controlled comparisons, setups with Tuist caching consistently outperformed those without it.  

This synergy between selective testing and binary caching dramatically improved developer productivity. Where we once faced slowdowns, we now had a seamless, accelerated workflow.  

Moving forward, we’ll work closely with the Tuist team to integrate our solution with their selective testing feature. Their implementation, which relies on a more accurate change detection system based on file-system fingerprinting, will further enhance the precision and efficiency of our testing workflows.  

<img style="max-width: 600px" src="/marketing/images/blog/2024/12/16/trendyol/with-without-cache.webp" alt="With/Without Cache Comparison for Each Development MRs"/>

## Developer Experience

From a developer’s perspective, these enhancements have a tangible impact on everyday work. With selective testing and binary caching, developers spend less time waiting on builds and more time iterating on features or exploring solutions. Shorter feedback loops mean they can validate ideas quickly, focus on delivering quality, and better manage the complexities of a growing codebase — all without feeling down by slow, repetitive processes.

For example, consider a developer looking to write and run UI tests. Thanks to Tuist’s caching capabilities, generating and opening a clean Xcode environment and start running UI tests now takes around 30 seconds — an experience that would have been nearly impossible before, when the same process took at least 15 minutes for a project of this scale.

Additionally, our CI build times have been reduced by 65%, decreasing from **30 minutes to just 10 minutes**. This significant improvement allows our CI pipelines to run faster, enabling quicker integrations and deployments.

## Self-hosted [Tuist Server](https://docs.tuist.dev/en/server/introduction/why-a-server) for speed and security

Our Tuist instance is [self-hosted](https://docs.tuist.dev/en/server/on-premise/install) within our internal infrastructure. This setup ensures ultra-fast cache transfers over our internal network and guarantees compliance with our security standards. As a result, we enjoy the performance benefits of caching without any external dependencies or potential security concerns.

## Looking Ahead

Our work with Tuist shows how investing in the right tools can lead to significant improvements in developer productivity and experience. We’ll continue refining our strategies, exploring new techniques, and integrating with other testing methodologies. As we learn and evolve, we’re committed to sharing our insights with the broader community.
