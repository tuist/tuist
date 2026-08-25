---
title: "The physics of build systems"
category: "engineering"
tags: ["engineering", "build-systems", "incremental-builds", "remote-caching", "remote-execution"]
excerpt: "Why build graphs, incremental builds, remote caching, and remote execution decide whether a build feels fast."
author: pepicrft
og_image_path: /marketing/images/blog/2026/08/19/og.png
live: true
---

At first, a build looks simple. Change a file, run a command, and a compiler turns the source into something you can ship or test. On a small project, that is close enough to the whole story. The machine has work to do, it does it, and a few moments later you have an answer.

Then the project grows. A change that should be local wakes up half the repository. A machine with more processor cores does not make the build noticeably faster. A cache makes some builds fly and seems to do nothing for others. At that point, it is tempting to think there must be one slow compiler, one badly configured cache, or one sufficiently large machine that will make the problem go away. Usually there is not.

In our [last post](/blog/2026/06/30/three-build-systems-one-graph), we introduced [Once](https://github.com/tuist/once), our prototype for making remote caching and execution accessible without asking people to replace the build systems they already use. Building it has forced us to get more precise about what actually makes a build fast.

If object storage is cheap, why not put a cache there and call it done? Will adding more processor cores make a build faster? If a continuous integration provider already offers a cache, what is missing? And if a project is already using a remote cache, why can the build still feel slow?

Start with a graph of tasks. On its own, it is only a description. The moment it meets a machine, the description turns into work, and the machine has only so much capacity to give it. Those constraints are the physics of build systems.


## The parameters of a build

Start with computation. We will come back to moving data later. Take a small target with two source files. Before it can produce an executable, it has to compile both files, then hand their object files to the linker. The build engine sees three tasks: two compilations with no relationship to each other, and a link task that needs the output of both. That relationship is the **graph**. It is not just a convenient way to describe a build after the fact. It decides what the machine is allowed to do at any given moment.

The simulator below uses generic task names. What matters is not whether a task is a compilation, a link, or something else. It is how much work the task has, what must finish before it can begin, and what the machine has available to run it.

Try changing the machine and the number of tasks below. Every task in this model takes the same amount of time. It starts with three tasks: two can run immediately, while the third waits for both. As you add tasks, the graph grows wider and deeper. More work becomes available at once, but more layers also have to wait for the work before them. Extra processor cores can help with the first part. They cannot remove the second.

<.live_component module={TuistWeb.Marketing.Components.BuildGraphLab} id="build-graph-lab" />

Say each task contains the same amount of **work**, enough to occupy one processor for ten seconds. On a machine with one processor core, the two initial tasks have to take turns, and the final task runs last. The build takes thirty seconds. Increase **processor speed** and each task finishes sooner. Add a second processor core and the two initial tasks can run together, so the final task begins after ten seconds and the whole build takes twenty. This is the result people expect when they buy a bigger machine, and it is real, provided the build has enough independent work to keep the machine busy.

Now give that same build thirty-two **processor cores**. It still takes twenty seconds. At the start, only two tasks are ready. When they finish, only the final task is ready. The rest of the machine is idle because no scheduler can start a task before the input it needs exists. Large builds have thousands of tasks instead of three, but they are subject to the same limit.

There are two useful ways to see that limit. One is the total amount of work divided across the processor cores. If enough tasks are ready, more cores lower that number. The other is the longest chain of tasks that must happen in order. More cores cannot shorten that chain. A build cannot finish before either limit allows it to.

> **The graph is part of the performance budget.** It decides which tasks can use the machine at the same time and which must wait. Buying a faster machine or adding processor cores is tempting because it is immediate. But if the graph does not expose enough independent work, that extra capacity sits idle. Make the graph easier to run first. Then bigger machines have something to accelerate.

In the simulator, a unit of work is one second of processor time on a reference machine. This is only a model. In a real build, recorded processor time is a useful estimate, but wall-clock time also includes waiting for dependencies, memory pressure, scheduling, and eventually moving data. Caches and networks change the picture too. We will get to them, but the graph comes first.

## Where the work comes from

A clean build, where every task has to run, is a useful starting point. But most developers do not work that way. They change a file, run the build again, change another file, and run it again. An incremental build looks at that change, finds the part of the graph it can affect, and leaves everything else alone. It still has to answer two questions: what needs to rebuild, and when can the required work run? They are different decisions, a distinction explored in [Build Systems à la Carte](https://simon.peytonjones.org/assets/pdfs/build-systems-original.pdf).

For one changed file, the affected part of the graph contains the task that reads it and every downstream task whose result could now be different. It is usually much smaller than the graph for the whole project. That is what incremental compilation buys us. It removes tasks from the build, and it can shorten the **longest dependency path** that remains. It cannot turn a dependency into independent work, but it can make that dependency irrelevant for the change in front of you.

<.live_component module={TuistWeb.Marketing.Components.IncrementalBuildLab} id="incremental-build-lab" />

Over time, the number that matters is not the cost of one arbitrary edit. It is the **cost of the edits a team actually makes**, weighted by **how often they happen**.

> **An incremental build is a distribution, not a single number.** A slow path that nobody changes is less important than a moderately slow path that developers touch all day.

There are two dimensions to a build: the graph, and the way that graph changes over time. The graph tells us the cost of one change, what has to rebuild, what can run in parallel, and what must wait. History tells us which changes the team actually makes. A shared module with many downstream dependents might be exactly what the project needs. It becomes an everyday cost only when it changes often, or when rebuilding it lands on a long path through the build. Put those two dimensions together and the questions become useful: which modules change most, how far do those changes travel, and which ones add time to a build already waiting on other work?

Looking at a graph or a build in isolation misses that intersection. A graph can show what might be expensive. An individual build can show what happened once. Neither says whether developers regularly pay that cost. [Build Insights](https://tuist.dev/en/docs/guides/features/build-insights) keeps the history of local and continuous integration builds, so the graph can be read alongside the way a project is actually used. At Tuist, we do not think caching and execution are enough on their own. Connecting a project should also give a team the data it needs to make better decisions about its setup.

Architecture turns this into a design problem. Shared foundations need to be small and stable, while fast-moving code needs boundaries that keep its changes from waking up the rest of the project. Then the cache and the extra machines have something worthwhile to accelerate. We will come back to the trade-offs behind those choices in a future post.

## Incrementality across worktrees

Open a feature, a review, and a small fix at the same time. Most files are unchanged between them. So are the dependencies, compiler, and a surprising amount of the work. Worktrees let those copies coexist without stepping on one another, but a build system usually meets each copy as if it were a new project.

There are two ways to carry work from one build to the next. **Incrementality by location** keeps mutable state in a build directory and benefits only when the next build returns to that directory. A second worktree has a second directory, so it starts without the first worktree's incremental state. **Incrementality by identity** names the result of a task by the inputs, toolchain, settings, and dependencies that produced it. Two worktrees can keep their own graphs and bookkeeping, but still ask for the same result.

<.live_component module={TuistWeb.Marketing.Components.IncrementalityModelsLab} id="incrementality-models-lab" />

Xcode is a familiar example of the first approach. Its DerivedData directory holds the build products and bookkeeping that make a later build incremental. Another checkout usually has another DerivedData directory, even when the source trees are nearly identical. [Swift Package Manager](https://www.swift.org/documentation/package-manager/), [Cargo](https://doc.rust-lang.org/cargo/reference/build-cache.html), and [Mix](https://hexdocs.pm/mix/Mix.html) also use local build directories. The normal consequence is simple: worktree B rebuilds work already completed in worktree A.

Sharing one directory changes the failure mode, rather than creating reuse. Two builds that point at the same directory have to coordinate updates to mutable state. The safe response is a lock: one build waits while the other changes the bookkeeping.

> **A shared build directory is a queue, not a cache.** It protects mutable state, but the second build still waits for the first.

Xcode's compilation cache uses the second approach for cacheable compiler work: it looks up a result by its content-addressed identity rather than through a worktree's DerivedData directory. Bazel, when it uses a disk or remote cache, does the same. Its [action cache and content-addressable storage](https://bazel.build/remote/caching) keep the lookup from an action to its result separate from the output files themselves. That is why another checkout can reuse the work without borrowing the first checkout's build directory.

The boundary is not native tools on one side and Bazel on the other. Go and Gradle have forms of action caching too, and Cargo can use `sccache` to share built dependencies. Go's [build cache](https://pkg.go.dev/cmd/go#hdr-Build_and_test_caching), for example, lives outside the project and is safe for concurrent builds. But unless a build uses `-trimpath`, the path of a local package can end up in debug information. Two worktrees with the same source are therefore not always asking Go for the same result. What matters is where a tool puts the state it needs to reuse work.

For tools that keep that state in a directory, the obvious answer in continuous integration is to keep the directory around. The next job mounts a volume with the last build's outputs and database. From the tool's perspective, it looks like the previous build never ended. We will call this a sticky volume. It makes a directory-scoped build feel incremental. It does not make the work inside that directory broadly reusable.

## Making a build directory stick

The idea is appealing because it can be effective quickly. A branch can start from a fork of the volume that its base commit produced, then keep its own volume from there. Its next build lands on a runner that can mount it. Dependencies are already fetched, generated files are still there, and an incremental compiler sees the state it expects. The difficulty appears when there is more than one plausible volume. Should a pull request inherit its branch's last build, the main branch, or the closest common commit? If every branch gets its own volume, each one starts cold and storage grows with the number of active branches. If they all share one, the build system is back to locking a mutable directory.

<.live_component module={TuistWeb.Marketing.Components.StickyVolumeLab} id="sticky-volume-lab" />

The volume also becomes a **scheduling constraint**. A volume that can be written by one node restricts where a job can run. A shared read-write volume has different storage and concurrency requirements. [Kubernetes makes those choices explicit through volume access modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/). The runner still has to choose the right volume, place the job on a machine that can mount it, and prevent two writers from corrupting the same state.

That is **operational complexity**, not cache configuration. Someone has to create and retire volumes, choose which history a job inherits, keep data close to the machine that needs it, and coordinate concurrent jobs. [Tuist Runners](https://tuist.dev/en/docs/guides/get-started/tuist-runners) handles that runner infrastructure and connects jobs to a cache shared with developer machines. The job can reuse valid results without a team having to select and mount yesterday's mutable build directory.

There is also a **correctness boundary**. A persistent build directory is not automatically flaky, but it preserves more than source files. It can hold paths, software development kit state, compiler outputs, and assumptions about the machine that last wrote to it. A sound build system notices the difference and rebuilds. A missed input can turn into the kind of failure that only appears on one runner, after one particular sequence of jobs. Absolute paths and undeclared environment variables are common reasons shared caches either miss or reuse the wrong thing. [Gradle's cache documentation](https://docs.gradle.org/current/userguide/build_cache.html) treats both as part of making a task relocatable.

> **A sticky volume does not make a build system share work. It makes one runner remember it.**

Persistent volumes are still useful. They are a good home for downloads, source mirrors, and other state deliberately designed to survive a new checkout. But they leave the platform choosing a history for every job and carrying the cost of that choice. A task-result cache has a narrower question: are these inputs the same? If they are, it can reuse the result wherever the next build happens to run. That is the second model in practice: reuse follows the identity of the work, not the directory that happened to run it last.

## The distance to a cache

A task-result cache makes reuse portable, but it changes the question. The build no longer needs the previous directory. It needs a result that may be somewhere else. That brings us back to the question from the beginning: if object storage is cheap, why not put the cache there? Object storage can hold the artifacts, and often should. But the price of keeping those bytes says almost nothing about the time it takes to serve a build.

Cost changes with the traffic shape too. Many managed object stores charge not only for bytes at rest, but also for requests, retrievals, transfer, and sometimes replication. A cache full of small artifacts can turn a modest amount of stored data into a great many operations. That may be immaterial for one team and material for another, but it is another reason to evaluate the cache path, not only the storage price.

Every remote cache hit has two time components. **Latency** is the time spent waiting for a request to reach the cache and a response to begin. **Bandwidth** is how quickly the artifact can move once that response arrives. A useful lower bound for a cache hit is:

$$
T_{\mathrm{hit}} \geq R \times L + \frac{S}{B}
$$

Here, $R$ is the number of request-response steps that cannot overlap, $L$ is latency, $S$ is the number of bytes to transfer, and $B$ is the effective bandwidth. It is a lower bound, not a prediction. Real cache hits also pay for cache lookup, decompression, and work that cannot be parallelized.

<.live_component module={TuistWeb.Marketing.Components.CacheTransferLab} id="cache-transfer-lab" />

When $R \times L$ dominates, the cache is **latency-bound**. A result split across thousands of small blobs can spend much of its time waiting for requests, unless the cache client batches metadata, reuses connections, prefetches, and downloads in parallel. When $\frac{S}{B}$ dominates, it is **bandwidth-bound**: artifact size and the available network throughput decide how long the transfer takes. Some lookups still sit on the dependency path, so their latency lands directly on wall-clock time. Concurrent requests can help throughput, and keeping compute in the same region reduces latency, but neither makes a distant object store behave like a local file system.

That is what **infrastructure collocation** means here. Cache and execution should sit on a short, high-bandwidth network path. In [Tuist Runners](https://docs.tuist.dev/guides/features/runners), compute and cache sit on the same private network. Keeping latency low and bandwidth high is part of the environment we operate, not a setting we ask a team to tune after the fact. But runners are not the whole picture. Developer machines can be spread across regions, and remote coding environments such as [Codex](https://openai.com/codex/) and [Claude Code](https://www.anthropic.com/claude-code) may reach a cache over the public internet. They should share the same valid results as the runners, but they cannot all be close to one central cache at once.

This is why we are building [Kura](https://github.com/tuist/tuist/tree/main/kura) as a decentralized cache mesh. A Kura node serves hot reads from its own disk and replicates artifacts and metadata to its peers. Kura is designed to sit beside our runners and to be deployed across regions, so each environment can have a nearby cache path while still sharing results with the rest of the team. In terms of the earlier bound, it is designed to reduce $L$ without giving up the shared history that makes a remote cache useful in the first place.

<.live_component module={TuistWeb.Marketing.Components.KuraNetworkLab} id="kura-network-lab" />

> **A remote cache hit is only a win when retrieving the result is faster than producing it again.**

## The limits of one machine

Collocation makes a cache hit fast. It does not help when there is no result to fetch. New work, invalidated work, and a task nobody has run before still need a machine. The limit returns to where we started: the finite number of processor cores in the environment that started the build. That machine can run the tasks that are ready in the graph, and no more.

**Remote execution** is the next step. Instead of keeping every cache miss on the machine that started the build, the build system can send a ready task to a pool of workers. Those workers need to be warm: they need the right toolchain, system image, and enough capacity to begin without first reconstructing the environment. They run the task and return the result to the shared cache. More workers help only when the graph has enough ready work to fill them, just as more processor cores help only when one machine has enough independent work. A long dependency chain still runs one step at a time.

> **A remote cache avoids work that has already been done. Remote execution gives the work that remains more places to run.**

This is not a common capability in native toolchains. [Bazel's remote execution support](https://bazel.build/remote/rbe) is explicitly designed to distribute build and test actions across multiple machines. [Buck2](https://buck2.build/docs/users/remote_execution/) can use the same open remote-execution protocol to run actions remotely or locally. In both cases, the build describes enough about an action to move it safely: the inputs, outputs, toolchain, settings, and environment it needs. That is what lets a worker execute a task without borrowing the state of the machine that requested it.

Most native toolchains can parallelize compiler work on the machine they were started on, but do not offer this as the normal way to run a build. Remote caching can still cut the work dramatically, but cache misses remain limited by the processor cores in one environment. Remote execution is the extra mile: a way to turn a wide part of the graph into work that a fleet can absorb, provided those workers are close to the cache and ready when the work arrives.

## What this means for teams

None of this makes optimizing the graph optional. Caching removes repeated work, and remote execution adds capacity for the work that remains. Neither can make a deep chain run in parallel or stop a small change from waking up much of the project. The graph still sets the shape of every build; the history of changes tells us whether developers pay the cost often enough to care. That is why insights over time matter. We need the graph alongside build traces and real changes, not one isolated run, to see what should be fixed before buying faster hardware or more infrastructure.

Tools that keep incremental state in a directory can be given sticky volumes, and that can be useful. But it trades an ordinary cache question for a scheduling problem: someone must maintain the volumes, decide which history a job inherits, keep it near compatible machines, and prevent concurrent writers. Tools with **incrementality by identity** can share results through a cache instead. Then latency, bandwidth, and the cost of moving artifacts are the variables to manage. The more granular the artifacts, the more that placement matters: one build can turn into thousands of small lookups and transfers rather than a few large ones.

> **Infrastructure is a multiplier, not a replacement for a graph that makes useful work available.**

Xcode's compilation cache already brings identity-based reuse to native Xcode projects and can deliver cache gains close to the systems built around remote caching. What it does not provide today is distributed execution. That remains the broader gap for native toolchains: most were designed around a developer building on one machine and still have work to do before they can use the amount of parallel build work a modern organization produces. People often ask us whether Xcode's compilation cache will grow into that kind of system. We do not know. It is a toolchain decision, and we do not know when, or whether, Apple will prioritize it.

That uncertainty matters more now that coding agents can produce changes faster than many projects can validate them. If build feedback is already the bottleneck, [Bazel](https://bazel.build) and [Buck2](https://buck2.build) are sensible options because remote caching and remote execution are part of the model today. The trade-off is adoption: both ask a project to describe its build in their rules. If that is more change than a team can take on, we are prototyping [Once](https://github.com/tuist/once) as a different entry point. Once works with an existing project and the scripts it already has, so a team can describe its automation gradually and connect it to caching and execution without first replacing the build system underneath. It is early, and we are looking for teams that feel this pressure and want to try it. Email us at [contact@tuist.dev](mailto:contact@tuist.dev).

One condition sits underneath all of this. A remote cache or remote worker is only safe if a task's identity is real. **Hermeticity** means accounting for every input a task needs. **Deterministic hashing** means those declared inputs, together with the toolchain and settings, always produce the same cache key. We will look at both in a future post, along with the other constraints that make distributed builds fast without making them wrong.
