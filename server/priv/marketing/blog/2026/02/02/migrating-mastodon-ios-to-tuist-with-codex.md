---
title: "Codex migrated Mastodon iOS to Tuist, cutting clean builds 80%"
category: "engineering"
tags: ["tuist", "migration", "ios", "codex", "cache"]
excerpt: "We gave Codex the Mastodon iOS client and asked it to migrate the project to Tuist generated projects, enable caching, and benchmark the results. Here is what happened."
author: pepicrft
og_image_path: /marketing/images/blog/2026/02/02/migrating-mastodon-ios-to-tuist-with-codex/og.jpg
highlighted: true
---

People have asked us many times why we haven't built an automated migration path to [Tuist generated projects](https://docs.tuist.dev/en/guides/features/projects). The honest answer is that real-world Xcode projects are messy. They are full of implicit configuration, one-off build settings, and decisions that made sense at the time but are hard to detect from the outside. For years, that kept migrations manual and made teams hesitant to adopt generated projects, even when they wanted the [module cache](https://docs.tuist.dev/en/guides/develop/build/cache) and the productivity gains that come with it.

We've been thinking about this differently since coding agents became capable enough to hold context across long feedback loops. What if the agent could do the mechanical work of migration while we focus on defining the constraints and validating the output? If that works, Tuist handles the complexity of Xcode projects, agents handle the tedium of adoption, and developers get faster workflows without the friction of a manual migration.

We decided to test this on the [Mastodon iOS client](https://github.com/mastodon/mastodon-ios). The resulting project is [public on GitHub](https://github.com/tuist/mastodon-ios-tuist). Not a toy project, not a demo. A real app with multiple frameworks, extensions, third-party dependencies, and all the quirks that come with a production codebase. The goal was a generated workspace that builds, runs, and benefits from caching. We also wanted to capture the process in a reusable [skill](https://docs.tuist.dev/en/guides/features/agentic-coding/skills) so the next migration doesn't start from scratch.

## What we asked Codex to do

We didn't hand Codex a step-by-step checklist. We gave it a set of outcomes: produce a Tuist-generated project that stays as close as possible to the original, integrate dependencies through Xcode project primitives so they can be cached as binaries, validate that the app actually launches on a simulator, and write a `skill.md` that captures the migration knowledge for future use.

The work ran on February 2, 2026 using [Codex](https://openai.com/codex/) 5.2 with GPT-5 as the underlying model. That detail matters because a migration like this isn't just about compiling. It requires understanding feedback loops, holding state across errors, and making judgment calls when things break. This was a good test of whether the model could handle that without constant human supervision.

## How it actually went

The first step was establishing a baseline. The original Xcode project compiled and the app launched on the simulator. Having that baseline gave us a reference point for the benchmark and confirmed we were starting from something healthy.

From there, the agent extracted build settings into `.xcconfig` files and wired them back into the target definitions in `Project.swift`. This follows our [migration guidance](https://docs.tuist.dev/en/guides/features/projects/adoption/migrate/xcode-project), which recommends xcconfig extraction because it preserves the settings hierarchy and keeps the manifest readable. Then it created the initial `Tuist.swift`, `Project.swift`, and `Tuist/Package.swift`, mapping each target into the Tuist graph.

The first `tuist generate --no-open` produced a workspace. The first `xcodebuild` run compiled. And then things started breaking, which is exactly what happens in real migrations.

### The missing class that wasn't missing

The first failure was a missing `TimelineListViewController` referenced by `DiscoveryViewModel`. The agent had excluded a directory called "In Progress New Layout and Datamodel" because it looked like unfinished work. Reasonable assumption, wrong conclusion. The class lived in that directory, and the original Xcode project included it while excluding only one specific file from the folder.

What was interesting here was watching the agent work through it. It didn't guess. It went back to the pbx structure, inspected the exception set, and adjusted the source glob to mirror exactly what the original project did. The compile errors disappeared.

### Resources, sources, and boundary confusion

The second round of errors was subtler. `.intentdefinition` files were being treated as resources when they needed to be sources. `.xcstrings` files were getting shadowed by `.strings` globs under a broader resource directory. Settings bundles were being treated as individual files rather than folder references.

Each of these was straightforward to fix once identified, but they are a good illustration of why migrations are tricky. The mistakes aren't about code logic. They are about boundaries: where sources end and resources begin, what counts as a file versus a folder reference, which build phase something belongs to.

## Unlocking cache, the whole point

The migration was never just about ending up with a more manageable modular project. It was about bringing optimizations like caching so that clean builds become fast by default. And the dependency issues that surfaced during cache warming were some of the most instructive parts of the process.

`UITextView+Placeholder` produced an invalid product name because the `+` character wasn't being sanitized the way SwiftPM does it. This was completely invisible in the original Xcode project and only surfaced once Tuist took over package integration. It turned out to be a bug in Tuist's target name sanitization. We fixed it directly in the Tuist codebase as part of [the same PR](https://github.com/tuist/tuist/pull/9326) where we wrote this blog post. We like that. The migration improved the tool itself.

With those fixes in place, `tuist cache` warmed the binaries and `tuist setup cache` enabled the [Xcode compilation cache](https://docs.tuist.dev/en/guides/features/cache). Then we benchmarked.

## The benchmark

We used [hyperfine](https://github.com/sharkdp/hyperfine) for repeatability. Both scenarios ran three times as clean builds with `xcodebuild clean build` and a dedicated `-derivedDataPath` per scenario.

**No-cache baseline:** the Tuist-generated workspace with the cache profile set to `none`, derived data wiped between runs, and Xcode compilation cache disabled.

**Cached build:** the `all-possible` cache profile so only the app and its extensions built from source, with Xcode compilation cache enabled. Before each run, local binaries and the compilation cache directory were removed so artifacts were pulled from the remote cache.

The commands looked like this:

```bash
tuist setup cache
tuist cache

hyperfine --runs 3 --warmup 1 \
  --prepare 'rm -rf DerivedData-NoCache && tuist generate --no-open --cache-profile none' \
  'xcodebuild clean build -workspace Mastodon-Tuist.xcworkspace -scheme Mastodon -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath ./DerivedData-NoCache COMPILATION_CACHE_ENABLE_CACHING=NO COMPILATION_CACHE_ENABLE_PLUGIN=NO'

hyperfine --runs 3 --warmup 1 \
  --prepare 'rm -rf DerivedData-Cache ~/.tuist/Binaries ~/Library/Developer/Xcode/CompilationCache.noindex ~/Library/Caches/com.apple.dt.Xcode/CompilationCache.noindex && tuist generate --no-open --cache-profile all-possible' \
  'xcodebuild clean build -workspace Mastodon-Tuist.xcworkspace -scheme Mastodon -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath ./DerivedData-Cache COMPILATION_CACHE_ENABLE_CACHING=YES COMPILATION_CACHE_ENABLE_PLUGIN=YES'
```

**Results:**

| Scenario | Mean | Min | Max |
|----------|------|-----|-----|
| No cache | 110.8s | 95.5s | 132.8s |
| Cached | 22.3s | 21.0s | 24.5s |

That is a **4.98x speedup** and a **79.9% reduction** in clean build time.

A caveat worth being honest about: cache effectiveness depends on how modularized the project already is. If most of your code lives in a single app target, there is less to cache. Mastodon has several internal frameworks, but the app target itself is still large. Teams that invest in smaller targets and clearer module boundaries should see even larger gains.

## The launch matters more than the build

A project that compiles is not the same as an app that works. After the workspace built successfully, the agent installed the app on the simulator and launched it. It crashed immediately with an unrecognized selector, `processCompletedCount`, coming off `NSUserDefaults`. Since Tuist integrates dependencies as Xcode-native targets and defaults to static linking, the linker was stripping object files that contained only Objective-C categories without class definitions. The category methods simply disappeared from the binary. As [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html) explains, this is expected behavior. Our [dependency documentation](https://docs.tuist.dev/en/guides/features/projects/dependencies#objectivec-dependencies) covers this in more detail.

The fix was adding `-ObjC` to `OTHER_LDFLAGS` in the shared project xcconfig, which forces the linker to load all object files from static libraries. After that, the app launched and stayed up. This is why we treat runtime validation as a non-negotiable step. It catches the class of issues that no amount of static analysis will surface.

## The skill that outlives the project

The most valuable output of this migration isn't the Mastodon workspace itself. It is the skill file that captures how to do this again.

The agent wrote `skill.md` as a migration guide that starts where a real engineer would start: with a baseline build, a target inventory, and a realistic set of constraints. It focuses on what tends to go wrong, how to detect it, and how to keep the generated project aligned with the original. It intentionally avoids caching instructions so it stays focused on migration mechanics.

This is the part that compounds. The agent does the work, but the skill makes the work repeatable.

## What we took away from this

If this story reads like a sequence of obstacles, that is because real migrations are. But stepping back, what stands out is that we have tools today that simply didn't exist a year ago. A coding agent took a production iOS app, migrated it to generated projects, resolved dependency bugs, validated the app at runtime, and helped us shave 80% off clean builds. The whole thing took about four hours.

That changes the calculus for teams. Migrating used to mean weeks of careful manual work, which is why many teams never got around to it even when they knew the gains were there. Now a few hours of agent time can get you to a place where both your developers and your CI hardware are being used more efficiently. The humans spend less time waiting on builds, and the machines spend less time rebuilding things that haven't changed.

We're going to run this playbook again on other projects. Each time we do, the skill gets sharper, the edge cases get smaller, and the process gets more predictable.

## Want us to migrate your project?

If you have an iOS project and would like us to run this same process on it for free, we'd love to hear from you. It doesn't have to be open source. The only thing we ask is that we can write about the experience, keeping any sensitive information private. We get to sharpen the skill and share the story, and your project gets faster builds with caching enabled. Reach out at [contact@tuist.dev](mailto:contact@tuist.dev).
