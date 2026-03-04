---
title: "The Three Layers of Developer Productivity"
category: "vision"
tags: ["vision", "productivity", "infrastructure", "cache", "compute", "toolchain"]
excerpt: "Most companies optimize developer productivity by throwing faster machines at the problem. But productivity has three layers, and ignoring the hard ones means wasting the easy ones."
author: pepicrft
---

When an organization grows past a certain size, someone eventually says the words out loud: "We need a platform team." It happens when builds start taking too long, when flaky tests erode trust, when onboarding a new engineer takes a week instead of a day. The toolchain that once felt invisible starts becoming the loudest thing in the room.

I joined one of those teams at [Shopify](https://www.shopify.com). It was called Mobile Tooling, part of a broader group called Dev Acceleration. The premise was simple: if you have hundreds of engineers using build systems, test runners, and deployment pipelines every day, you need a team that ensures those tools are used in the most optimal way possible. Human capital is expensive. You do not want engineers sitting idle waiting for a build to finish. You do not want them rerunning a test suite because they cannot trust the results. You want every resource, human and machine, working at its best.

The reason these teams exist comes down to two things.

First, understanding developer tooling at a deep level is rare. You need years of experience with build systems, test runners, and the kinds of failures that only emerge at scale. Knowing how a compilation graph distributes work across cores, understanding why a particular dependency ordering creates bottlenecks, recognizing when a configuration choice made two years ago is now costing you minutes on every build. **This is not knowledge you pick up in a weekend.** And asking a product engineer to context-switch into this work is a big stretch. It is like asking a chef to also be the plumber. They could probably figure it out, but you are wasting their best skills.

Second, by the time you form a platform team, the codebase is already large and there is a lot of activity happening. Making meaningful improvements requires changes in configuration, changes in tool versions, reorganizing code. Doing all of that while business demands keep rolling in is incredibly difficult. It is surgery on a patient who refuses to stop running.

## The reactive trap

What happens in most organizations is that the platform team, if it exists at all, works reactively. Something breaks, someone complains, the team investigates. The tools themselves are not designed for observability. The interaction model is you and a terminal. You configure a build system once, you grow the codebase for months or years, and you rarely revisit that initial configuration. Performance degrades slowly, invisibly, like a frog in warming water.

Think about it like a factory floor. Imagine a manufacturing plant where nobody monitors the machines. They were set up correctly on day one, and for a while everything runs smoothly. But over time, bearings wear down, belts loosen, calibrations drift. Because nobody is watching the telemetry, because there is no telemetry, the degradation accumulates silently. By the time someone notices that production has slowed by 30%, there is no single cause. It is a hundred small regressions stacked on top of each other, and untangling them is a nightmare.

This is exactly what happens with developer tooling. And with coding agents entering the picture, the problem has accelerated. Agents produce code at a velocity that human developers never reached. If any step in the process of turning that code into a compiled artifact or running tests to validate it is slow or unreliable, you diminish the returns of the entire agentic workflow. Flaky tests that an agent cannot trust. Builds that take twenty minutes when they should take three. These are not minor annoyances anymore. **They are bottlenecks that make expensive infrastructure less valuable.**

## Three layers

This is something we have been thinking about a lot at Tuist. Not just how to fix individual problems, but how to frame the entire space of developer productivity in a way that gives us and our users a shared mental model. Without a clear framework, it is easy to end up with a product that is a Frankenstein of features. A cache here, an analytics dashboard there, some CI integration over there. Everything loosely connected but lacking a coherent story. We needed a structure that would hold everything together and guide us as we expand into new ecosystems.

What we arrived at is that developer productivity operates in three layers, stacked vertically. Each layer has its own characteristics, its own economics, and its own relationship to the others.

Think of it like the human body. The toolchain is your form and technique: how efficiently you convert effort into movement. Compute is your muscles: raw strength and power. And cache is muscle memory: movements you have already learned that you do not need to think about again. A strong athlete with bad form wastes energy and gets injured. Perfect form still has a physical ceiling if the muscles are not there. And muscle memory is what lets you perform beyond what conscious effort alone allows, because you are not repeating work your body already knows how to do.

### The toolchain layer

This is the layer closest to your project. It is the interaction between your code and the build systems, test runners, linters, and all the tools that turn source files into something that runs. It is the least glamorous layer and the one that gets the least investment. Not because it is the least important, but because it is the hardest.

Going deep into the toolchain requires understanding every ecosystem individually. How Swift compilation graphs work is different from how Gradle resolves dependencies, which is different from how Vite bundles JavaScript. In networking, there is a concept called the narrow waist: the thin layer that sits between everything above and everything below, translating between the two. TCP/IP is the narrow waist of the internet. The toolchain layer is the narrow waist of developer productivity. It sits between your project and the infrastructure that builds it. But unlike TCP/IP, there is no universal protocol here. **Every ecosystem has its own narrow waist**, with its own data structures, its own performance characteristics, its own failure modes. You have to learn each one individually. There is no shortcut. This makes the toolchain layer unattractive for companies that need quick returns to meet investor expectations. You cannot raise a round, hire a team, and have ecosystem depth in six months. It does not work that way. We believe there is real value in making this investment, but it is value that compounds over years, not quarters. The trust you earn by going deep into an ecosystem, by contributing to the tools developers already use, by understanding problems at a level that most companies will not bother with, that trust is what turns into adoption and retention over time.

The tools themselves are typically not designed for observability. Your build system speaks to you through standard output. You see a wall of text, maybe some timing information if you are lucky, and that is it. All the rich internal data, the compilation graph, the dependency ordering, the parallelization profile, is flattened into a log stream. You miss most of what is actually happening.

And even when you can extract useful data, you need to understand it over time. Is a particular module a parallelization bottleneck? Maybe. But it depends on how often that module changes. If it changes on every commit, optimizing it is critical. If it changes once a quarter, it probably does not matter. Frequency is something you only know if you persist the data and analyze trends. **A single snapshot tells you almost nothing.**

This is the layer where we started at Tuist, and it is where we believe the most impactful work happens. We have gone deep into Xcode. We are going deep into Gradle. And as we expand into more ecosystems, we will do the same thing every time: understand the data structures the tools work with, observe them properly, and get to a point where we can proactively surface insights instead of waiting for someone to complain.

Most companies avoid this layer because each ecosystem requires dedicated investment. They prefer solutions that look the same everywhere. That preference is understandable. **It is also why the toolchain layer remains the most neglected.**

### The compute layer

If the toolchain layer is your form, compute is your muscles. This is the raw power where the action happens. Your developer laptop. Your CI runner. And increasingly, the sandboxed environments where coding agents execute their work.

Compute is where most of the money flows in our industry, because it is the easiest layer to invest in. It is tangible. You can measure it. You can compare specs. You can say "my machine has 32 cores and 64 GB of RAM" and feel like you have solved something. Companies compete on milliseconds of startup time, on core counts, on I/O throughput.

And it matters. Of course it matters. A faster machine compiles code faster, runs tests faster, everything faster. But compute alone has a ceiling, and that ceiling is determined by physics. You can buy the most powerful machine available, and your build still takes however long it takes to process everything from scratch.

Here is the part that I find genuinely fascinating: organizations pour money into faster compute while completely ignoring how their projects use that compute. If your compilation graph has one massive module that everything depends on, you will have one core working at full capacity while fifteen others sit idle waiting for it to finish. **That is an expensive machine doing very little work.** It is like a weightlifter with massive arms but terrible form. The strength is there, but most of it is wasted.

The compute market is getting crowded. CI companies that have invested in their infrastructure for years are now offering those environments for agent workflows. Sandbox companies like [Daytona](https://www.daytona.io/), [E2B](https://e2b.dev/), and others are providing boxes for agents. Product companies like Linear, Codex, and others are spinning up their own environments. Everyone is offering compute because compute is a relatively straightforward product to build and sell.

But when everyone is selling the same thing, differentiation becomes razor thin. Someone will always match your specs at a lower price. This is where companies that only do compute start to struggle. Their improvements become incremental: 200 milliseconds faster startup, 100 milliseconds less latency. Important, but diminishing.

### The cache layer

At some point, no matter how fast your machine is, you hit the physical ceiling. Your cores are saturated. Your I/O is maxed. And yet you are compiling or testing something that someone else, maybe even you ten minutes ago, has already done. From the perspective of using resources optimally, repeating that work is waste.

This is where caching enters. Build systems like [Bazel](https://bazel.build/remote/caching) pioneered remote caching years ago. Gradle has it. Xcode introduced compilation caching recently. The trend is clear: caching is becoming a standard capability across ecosystems.

The interesting tension with caching is that it introduces the network. You break through the physical ceiling of a single machine by distributing pre-computed results across a network. But in doing so, you make latency the new bottleneck. If you can pull a cached artifact in 5 milliseconds, caching is transformative. If it takes 500 milliseconds, you might be better off just rebuilding locally. **The gains from caching are directly proportional to how close the cache is to the compute.**

Going back to the body analogy: muscle memory only works if the recall is instant. If there is a delay between your brain sending the signal and your muscles executing the movement, you lose the advantage entirely. You might as well be learning the movement from scratch. Proximity between the memory and the muscles is everything.

This is why compute and cache must be colocated. They are not independent layers you can optimize separately. They have to work together, physically close, with minimal latency between them. A fast machine with a distant cache is not much better than a fast machine with no cache at all.

But low latency is only half the problem. The other half is access. A cache is only as useful as the number of contexts that can reach it. Today, your code builds in many places: your laptop, your CI runner, an agent sandbox, a colleague's machine. If the cache is only accessible from one of those contexts, you are still repeating work everywhere else.

This is where many existing solutions fall short. GitHub Actions cache, for example, is tightly coupled to CI pipelines. It lives inside the CI compute and can only be accessed from within a workflow run. Your developers cannot pull from it locally. An agent running outside of GitHub Actions cannot benefit from it. The cache exists, but it is locked inside a single context. That is not a cache infrastructure. That is a feature of a CI product.

**A cache worth building needs to be accessible from anywhere the action happens.** Multiple interfaces, multiple protocols, multiple entry points. Your build system should be able to reach it. Your IDE should be able to reach it. An agent running in a container somewhere should be able to reach it. The cache should be a piece of infrastructure that serves all compute, not a feature that serves one product.

## Why the framework matters

The reason we wanted to capture these three layers as a mental model is that without it, we risk building a product that lacks coherence. When you expand into new build systems, when you ship new features, when you make architectural decisions, you need something to anchor those choices. Which layer does this feature serve? How does it interact with the other layers? Are we neglecting one in favor of another?

Without this framework, you end up with a product that is a collection of loosely related tools. A cache that does not understand the toolchain. A compute layer that does not know about the cache. Analytics that show you numbers without telling you what to do about them. **Each piece works in isolation but the whole is less than the sum of its parts.**

With the framework, every decision has a place. When we jump into a new ecosystem like Gradle, we know exactly what we need to build: deep toolchain understanding, cache integration, and compute awareness. The same structure applies regardless of the technology. The specifics change, but the architecture does not.

## What we are building

At Tuist, we are designing the product so that you can choose the layer you need. You do not have to buy the whole stack. If you only want caching, you can deploy it close to your own compute and get the latency benefits without changing anything else. If you want compute and caching together, we will provide environments where they are colocated, so you do not have to think about proximity. It will just be fast.

And then we layer the toolchain understanding on top. This is the part that ties everything together. We do not just give you a fast machine with a cache. We make sure you are using those things in the most optimal way possible. We look at your build graphs, your test runs, your compilation patterns, and we surface the things that are wasting your resources. Not as a dashboard you have to check. As proactive insights that tell you what to fix and why.

This is the vision: we want to be the platform team that most organizations cannot afford to build themselves. Not a team of people you hire and retain and hope they stay long enough to accumulate the knowledge. A product that carries that knowledge, that watches your workflows, that understands your tools deeply enough to optimize them for you.

We are making this accessible to everyone. Not just the companies with hundreds of engineers and the budget for a dedicated platform team. Everyone. The team of five that just started a project and wants to build good habits from the beginning. The solo developer who does not want to spend a weekend figuring out why their builds got slow.

The three layers are simple enough to explain in a conversation. But they represent years of accumulated understanding of what actually matters for developer productivity. And they are the framework that will guide everything we build from here.
