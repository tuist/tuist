---
title: "Tuist Runners: Going down to the bare metal on macOS and Linux"
category: "product"
tags: ["product", "runners", "ci", "macos", "linux", "cache"]
excerpt: "Managed macOS and Linux CI runners with colocated caching and insights down to the metal. Invite-only while we grow capacity."
author: fortmarek
live: true
highlighted: true
cta_title: "Your CI, optimized for your workflows all the way to the bare metal."
---

Today, we're very excited to share what we've been building over the past months: **Tuist Runners**, managed macOS and Linux runners for GitHub Actions, GitLab CI, Buildkite, and more in the future. The Macs run in a rack that we own, in a data center in Berlin, and that rack has its own colocated cache nodes for the most optimal performance.

Getting here took us down a path we didn't expect to take when we started working on productizing caching three years ago. We went from making projects faster regardless of where they run, to buying Mac minis and racking them ourselves. This post is about why and how we did it, and what you get when your CI runs next to its cache on Tuist compute.

## Making projects faster, wherever they run

Tuist has always been about impeccable developer experience and productive developer environments. Long before runners were on our radar, we invested in optimizations that work in **any** environment: the [module cache](https://tuist.dev/en/docs/guides/features/cache) that turns your modules into prebuilt binaries, [selective testing](https://tuist.dev/en/docs/guides/features/selective-testing), the remote [Xcode compilation cache](/blog/2025/10/22/xcode-cache), the Gradle build cache, [test sharding](/blog/2026/03/25/test-sharding), and the build and test insights that tell you where the time goes in the first place. You can use all of these on your laptop, on GitHub-hosted runners, or on a CI fleet you manage yourself, and that's not changing.

But once the build stops doing unnecessary work, the remaining work changes its nature. Instead of compiling, your build is now mostly _fetching_: asking the cache whether an artifact exists, and downloading it if it does.

## Why cache proximity matters for CI

When we [launched the remote Xcode cache](/blog/2025/10/22/xcode-cache), we wrote that latency is key: the build system makes thousands, sometimes tens of thousands, of cache requests per build, and every single one pays for the round trip. We then built [Kura](/blog/2026/09/14/kura), our distributed cache, and placed it in regions close to where builds run.

However, there's a ceiling to how far that can go. When you don't own the environment the build runs in, the last stretch between the machine and the cache is someone else's network. Your artifacts travel over the public internet, share bandwidth with everything else that machine's provider is doing, and pay a round trip measured in milliseconds rather than fractions of one. We went deeper into these constraints in [The physics of build systems](/blog/2026/08/25/the-physics-of-build-systems).

The only way past that ceiling is to own both the machines that run the builds and the cache that serves them, placed right next to each other. We first tried to do this with what's available on the market: we ran the first version of Tuist Runners on rented Apple silicon and colocated cache nodes with that fleet as closely as the provider allowed. It worked, and it taught us a lot, but none of the rented options would work for us long-term. Renting a Mac mini costs about as much in a few months as buying one, and, more importantly, we'd always depend on someone else's rack layout, network, and how quickly they are able to provide us with new machines, like the recently-introduced M5 Pros.

In our own rack, the cache lives on two storage nodes, one on each top-of-rack switch. They run the rack's own Kura cache region, replicating with the rest of the Kura mesh, and they store the cache volumes that the runners attach to. When a Mac mini asks for a cache artifact, the request goes to its top-of-rack switch and straight to the storage node on it, with a round trip measured in fractions of a millisecond.

To get a feel for what that means for a build, pick a workload below and press play. The Xcode compilation cache makes many small requests, so it's dominated by the round trip, while the module cache downloads fewer, larger binaries, so it's dominated by bandwidth. The rack wins on both:

<.live_component module={TuistWeb.Marketing.Components.Posts.Runners.CacheDistanceRace} id="cache-distance-race" />

## How we got here

None of this happened overnight.

In 2025, we were heads-down on making builds do less work, wherever they ran. We kept improving the module cache and selective testing, shipped [build insights](/blog/2025/06/05/build-insights) so that teams could see where their time goes, and in October, launched the remote Xcode compilation cache. While benchmarking it, one thing kept showing up in the numbers: the cache was only as fast as the network between the cache and the machine itself.

At the beginning of 2026, we stepped outside of the Apple ecosystem. The Tuist CLI [started running on Linux](/blog/2026/02/16/linux) in February, and two weeks later, Tuist [came to Gradle](/blog/2026/03/02/gradle). Suddenly, the same question applied to Android teams, too: where do their builds actually run, and how far is that from the cache?

Earlier this year, we launched the first version of Tuist Runners, initially used just by ourselves, using macOS VMs on rented Apple silicon and Linux microVMs on bare-metal servers, both dispatched by the Tuist server.

The more we tried to squeeze as much performance as possible from the environments provided to us, the more we ran into the limits of machines we didn't own. We couldn't put the cache exactly where we wanted it, we couldn't choose the network in between, and when new hardware like the M5 Pro Mac minis came out, getting it was up to someone else. So in September, we [announced](/blog/2026/09/12/the-new-tuist) that we were going down to the metal.

It turns out that going down to the metal is much less about just buying machines for the rack and much more about everything around them. None of us had done this before. A few years ago, a team our size probably couldn't have taken it on, but today, so much of that knowledge is available through AI models. They didn't take away learning by doing, nor the operational work that goes well beyond designing the rack, but they made it possible for a small team like ours. The rest, we learned one conversation at a time:

- **A home for the rack:** We talked to colocation providers in Berlin and settled on NTT's Berlin data center. After a tour of the facility with the team, we had to walk their electrical engineers through how we'd give Mac minis, which have a single power supply, access to both of the rack's power feeds with our own transfer switches and switched PDUs.
- **Internet:** A rack comes with space and power, but not with an internet connection. We needed to sign a contract with a carrier to get a fibre cross-connect between their room and ours, coordinated between them and the data center.
- **The Mac minis:** We worked with the business team at our local Apple Store in Berlin to order and lease M5 Pro Mac minis in bulk, registered to enroll into our device management the moment they're turned on.
- **Insurance:** Expensive hardware sitting in a building we don't own needs to be insured, so we extended our electronics insurance to cover a colocation site.
- **Our own IP range:** Shortly after we took over the rack, a team with a GitHub IP allow list couldn't check out their code from our runners. So we became a RIPE member, got our own autonomous system and IPv4 range, and started announcing it from the rack over BGP. Every team now has a single, stable range to allow.

On October 6, we took over the rack. We loaded a shared car with rack shelves, cables, and a big blue IKEA bag of hardware, and drove to the data center, where the first boxes of Mac minis were waiting to be unpacked:

![On the left, a team member next to a car with its trunk open in front of the data center, with a blue IKEA bag of rack shelves on the ground. On the right, a Mac mini labeled ber1-runner-b01 sitting on a stack of Mac mini boxes inside the rack.](/marketing/images/blog/2026/10/29/runners/getting-the-rack-started.jpg)

And here's us on our way to the data center that day:

<video controls playsinline preload="metadata" poster="/marketing/images/blog/2026/10/29/runners/rack-install-day-poster.jpg" src="/marketing/videos/runners-rack-install-day.mp4"></video>

Our goal is to run this at industrial scale, but every fleet starts somewhere.

## Inside the rack

Here's our rack in Berlin. Click on any part of it to learn what it does:

<.live_component module={TuistWeb.Marketing.Components.Posts.Runners.RackElevation} id="rack-elevation" />

When the knowledge to build something like this is available to anyone, keeping our implementation closed isn't where the value lies. The value we provide is in packaging it all together, operating it, and offering a service that's ready to use. So **even our rack definition is open source**: the [site definition](https://github.com/tuist/tuist/blob/main/infra/rack-switch-fleet/sites/larch.json) describes every device, port, and power feed in the rack, and the [cable schedule](https://github.com/tuist/tuist/blob/main/infra/rack-switch-fleet/cables/larch.md) and the switch configuration are rendered from it. The code that takes a freshly unboxed Mac mini to a runner accepting jobs lives in the same [repository](https://github.com/tuist/tuist/tree/main/infra) as everything else we build. If you've ever wondered how to run Macs at scale, you're welcome to read along, and we'd love to hear your ideas.

## Beyond colocating the cache

When we started building runners, we didn't want to stop at colocating the cache, although that alone brings a lot of benefits. Owning the environment means we can optimize the parts of a CI job that have nothing to do with compilation, and that's where a lot of the time goes once your build itself is fast.

- **Cache volumes:** Every runner starts as a fresh, ephemeral VM, but that doesn't mean it has to start cold. Cache volumes are persistent disks, kept per repository, that a job attaches on start. The Xcode compilation cache, the module cache, and Gradle's caches each take a single step to keep on them, and you can add any other directory, like `node_modules`, under a key you choose. The runner prefers a machine that already holds your volumes, saves only what a job changed, and never makes a job wait for a volume to download.
- **Cached checkouts:** Cloning a large repository from scratch on every job adds up. Runners keep checkouts warm, so `actions/checkout` mostly fetches what changed.
- **Ecosystem-specific actions:** We build actions for the ecosystems we integrate with deeply. For example, [`tuist/install`](https://github.com/tuist/tuist/tree/main/.github/actions/install) installs your Swift package dependencies with [SwifterPM](/blog/2026/07/16/swifterpm) and keeps the resolved state on a cache volume. That brought SwiftPM resolution from **around two minutes down to just a couple of seconds**. And since it falls back to GitHub's cache everywhere else, the same step works on any runner.
- **Linux, too:** Linux jobs get cache volumes and cached checkouts, too, along with Docker, a pull-through cache for container images, and hardware-accelerated virtualization through `/dev/kvm`, so you can run Android emulators, including Gradle Managed Devices, without any setup.

## Build and CI insights, from code to the metal

Runners are not a separate product bolted onto Tuist. Because we own every layer, the insights go all the way down: from your builds and tests, through the CI job and its cache, to the metal and the node that ran the job. A job running on Tuist Runners shows up in the same dashboard as your build insights, test insights, and cache analytics: its steps, live logs, machine metrics, the cache volumes it used, and the builds and tests that ran inside it. When a job misbehaves, you can connect to the running machine and see what's going on. Having all of that context in one place is what lets you and your agents understand the whole system, rather than piecing it together across separate services.

And everything is agent-first. Through a [single MCP server](https://tuist.dev/en/docs/guides/features/agentic-coding/mcp), your agent can list runner jobs, read their logs and steps, look into cache volume analytics, and correlate all of that with your cache insights and build insights, then manage your runner profiles through the same MCP, the CLI, or the API. One MCP, and all of your CI and build system-specific data in one place.

So far, our focus has been on iOS and Android with Gradle. We believe that integrating deeply with an ecosystem is what makes the experience great: understanding a build system well enough to cache the right things, to make dependency installation fast, and to show insights that actually mean something to you. That's why we're taking the same approach as we expand to Elixir, [Rust](https://tuist.dev/en/docs/guides/get-started/rust-project), and [Bazel](/blog/2026/09/09/bazel), and to [Once](/blog/2026/09/12/the-new-tuist), our own build system.

## How to try Tuist Runners

We're still early in this journey and we're continuously adding Mac minis to ensure to meet the growing demand. This is a capital-intensive exercise and for now, we're keeping **Tuist Runners invite-only** to make sure we have enough capacity to onboard new customers.

That said, we'd love for you to take them for a spin. If you'd like an invite, send us an email at [contact@tuist.dev](mailto:contact@tuist.dev) or reach out in our [Slack](https://slack.tuist.dev), and tell us a bit about your project and your CI. You can also read more about how runners work in our [documentation](https://tuist.dev/en/docs/guides/features/runners).

And if you're already on GitHub Actions, adopting them is a one-line:

```diff
 jobs:
   build:
-    runs-on: macos-latest
+    runs-on: tuist-macos
     steps:
       - uses: actions/checkout@v4
       - run: tuist test
```
