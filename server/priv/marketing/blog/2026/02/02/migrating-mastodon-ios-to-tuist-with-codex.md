---
title: "4 Hours of Codex 5.2 Brought Mastodon a 63.9% Cache Improvement"
category: "engineering"
tags: ["tuist", "migration", "ios", "codex", "cache"]
excerpt: "A long-form story of migrating the Mastodon iOS client to Tuist generated projects with Codex, including the plan, the setbacks, the fixes, and the cache-backed benchmark results."
author: codex
og_image_path: /marketing/images/blog/2026/02/02/migrating-mastodon-ios-to-tuist-with-codex/og.jpg
highlighted: false
---

Many people asked us why we have not built an automated migration to Tuist generated projects. The reason is simple. Real world projects can be intricate, full of implicit configuration, and packed with one off decisions that are hard to detect and harder to migrate safely. For years, that kept migrations manual and made teams hesitant to adopt generated projects, even though they wanted access to a very performant module cache. This post is our attempt to change that story.

We still believe coding agents can migrate existing apps to Tuist generated projects so teams can benefit from Xcode caching and module caching without giving up the fidelity of their existing setups. If we are right, Tuist gets to manage the complexity of Xcode projects while agents take on the mechanical parts of adoption, and developers get faster workflows with less day to day friction. That is the bet.

We tested that bet on the Mastodon iOS client. The goal was ambitious by design. We wanted a real migration, not a demo. We wanted a generated workspace that builds and runs. We wanted caching turned on and doing real work. We wanted a benchmark with clean builds before and after. And we wanted the output to be reusable: a skill that can guide future migrations and a blog post that captures the reality of the process, not just the highlight reel.

## The plan we gave Codex

The plan wasn't a checklist of commands. It was a set of outcomes and constraints. Codex had to deliver a Tuist-generated project that stayed as close as possible to the original, with the goal of integrating dependencies through Xcode project primitives so that we could cache those as binaries, and a runtime validation that proved the app actually launches. We also asked Codex to output a `skill.md` that captures what matters during migration so the next project benefits from the same hard earned context.

## The migration, as it actually happened

We began with the baseline. The original Xcode project compiled and the app launched. That baseline mattered for two reasons. First, it gave us a reality check: the original setup was already healthy. Second, it gave us a point of comparison for the eventual benchmark. Codex executed the baseline build and captured the exact commands so the generated workspace could be validated the same way.

From there, Codex extracted build settings into `.xcconfig` files, then wired those configs back into the target definitions in `Project.swift`. This follows our migration guidance in [the docs](https://docs.tuist.dev/en/guides/features/projects/adoption/migrate/xcode-project), which explains why xcconfig extraction makes large projects easier to migrate and maintain. This was not just a mechanical reformat; it preserved the settings hierarchy, kept configurations aligned across targets, and made it easier to match the original Xcode project without cluttering the manifest.

Codex then created the initial `Tuist.swift`, `Project.swift`, and `Tuist/Package.swift` files, mapping each target from the Xcode project into the Tuist graph and integrating dependencies through Xcode project primitives so they could be cached as binaries. When those manifests were in place, Codex generated the workspace with `tuist generate --no-open` and ran `xcodebuild` to validate the first compile.

That early build compiled, but we quickly ran into the kind of migration issue that only shows up when you are strict about "staying close."

### The missing class that wasn't missing

The first real failure was a missing `TimelineListViewController`. The error was surfaced by `DiscoveryViewModel`, which referenced it directly. Codex had excluded the "In Progress New Layout and Datamodel" directory because it looked like unfinished work and the Xcode project contained exception sets that implied selective inclusion. That decision was wrong. The class lived in that directory, and it was needed. Codex fixed it by mirroring the pbx exception set exactly: include the directory and exclude only the explicit file that the project excluded. Once that change landed, the compile errors disappeared.

This was the first moment where the agent's behavior mattered. It did not guess. It followed the errors, inspected the pbx structure, and changed the source glob accordingly. No human input was required for the fix.

### Resources, sources, and intent definitions

The second set of errors was subtler. `.intentdefinition` files were being treated as resources when they needed to be sources. `.xcstrings` files were being shadowed by `.strings` globs under a broader resource directory. Settings bundles were being treated as files rather than folder references. Codex corrected each of these in `Project.swift`, regenerated the workspace, and re-ran the build to confirm they were resolved. Each issue was easy to fix once discovered, but they were instructive: migration mistakes are often about boundaries, not about code.

## Why caching was the point and what it took to unlock it

A lot of companies have a goal of using caching so their agents and developers get faster clean builds and tighter iteration loops. This migration was about making that possible, not just generating a new workspace. That goal also meant we had to resolve the dependency issues that only surfaced once Tuist took over package integration and cache warming.

The first fix involved `UITextView+Placeholder`. It shipped an invalid bundle identifier. This was invisible in the original Xcode project and only surfaced once Tuist took over package integration. Codex solved it by vendoring a local copy into `External/UITextView-Placeholder` and overriding the bundle ID through package settings. It restored a valid configuration without diverging from upstream code.

The second fix involved `MetaTextKit`. The ambiguous `XMLElement` error is a real compilation issue, not a caching artifact. It would have failed a normal build too, but we encountered it while warming the cache. Codex fixed it by vendoring a local copy of MetaTextKit and explicitly typing `Fuzi.XMLElement`. Again, this was a minimal patch, but it unlocked the cache. Both dependency issues were found by the agent and resolved without human input once the failures became visible.

Codex also updated Swift package mapping to sanitize the `+` character when deriving bundle identifiers, preventing invalid bundle IDs for packages like `UITextView+Placeholder`. Those changes were made directly in the Tuist codebase, with tests, and then pushed as a PR.

With those resolved, Codex warmed the cache using `tuist cache` and regenerated with the `all-possible` profile to maximize binary reuse. Then Codex benchmarked clean builds using hyperfine. The baseline was a clean build of the original Xcode project. A single run took 362.020 seconds. The cached build was run three times with a clean workspace build and a preserved module cache. The mean time was 130.741 seconds, with a minimum of 120.861 seconds and a maximum of 141.355 seconds. That is a 2.77x speedup and a 63.9% improvement. The magnitude of the gain matters less than the repeatability: it is now the default in the generated workflow.

We were careful about the benchmarking mechanics. We treated each run as a clean build, using `xcodebuild clean build` with a dedicated `-derivedDataPath` for each scenario. We warmed Tuist binaries once with `tuist cache`, then generated with `--cache-profile all-possible` so that the cached run used as many prebuilt modules as possible. For the no cache case we generated with `--cache-profile none`. We did not wipe Xcode's module cache between runs so the comparison reflected a realistic developer loop, but we did clean build products each time so the link and copy phases were fully exercised. Hyperfine made the sequencing repeatable and recorded the mean, min, and max.

The commands Codex used looked like this:

```bash
tuist cache

hyperfine --warmup 1 \
  --prepare 'tuist generate --no-open --cache-profile none' \
  'xcodebuild clean build -workspace Mastodon-Tuist.xcworkspace -scheme Mastodon -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath ./DerivedData-NoCache'

hyperfine --warmup 1 \
  --prepare 'tuist generate --no-open --cache-profile all-possible' \
  'xcodebuild clean build -workspace Mastodon-Tuist.xcworkspace -scheme Mastodon -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath ./DerivedData-Cache'
```

The migration took about four hours end to end. At our measured savings, each clean build saves about 231 seconds, or roughly 3.9 minutes. That means it takes about 62 clean builds to break even on the time cost of the migration. For a team of ten running two clean builds per developer per day, that is about three working days. If you translate that into cost using the [US Bureau of Labor Statistics median hourly wage for software developers, $63.59 in May 2023](https://www.bls.gov/oes/2023/may/oes151252.htm), the savings are about $80 per day or about $400 per week for that example team. This is an illustration, but it shows why teams are willing to pay a one time migration cost to unlock a faster loop that compounds on every build.

## Runtime validation

The moment that matters most is not the build. It is the launch. After the workspace built, Codex installed the app on the simulator and launched it. The first run crashed with an unrecognized selector, `processCompletedCount`, coming off `NSUserDefaults`. Codex traced it to ObjC categories defined in a static framework that were being stripped at link time. Codex fixed it by adding `-ObjC` to `OTHER_LDFLAGS` in the shared project xcconfig, rebuilt, reinstalled, and launched again. This time the app came up and stayed up. That is the difference between a build that looks fine and an app that actually works. We now treat runtime validation as a non-negotiable part of the process because it catches issues that static analysis will never surface.

## The timeline and the model

This migration took about four hours end to end. The baseline build alone took about six minutes. Warming the cache took under seven minutes. The cached clean builds averaged just over two minutes. The rest of the time was spent iterating on failures, regenerating the workspace, and validating runtime behavior.

We ran the work on February 2, 2026 using Codex 5.2 with GPT-5 as the underlying model. That matters because a migration like this is not just about compiling; it is about understanding feedback loops and holding state across errors. The model needs to be capable of managing that complexity without constant human supervision. This run showed that it can.

## The skill that outlives the migration

The output of this migration is not just a working project. It is the skill that captures how to do this again. Codex wrote `skill.md` as a migration guide that starts where a real engineer starts: with a baseline build, a target inventory, and a realistic set of constraints. It emphasizes what tends to go wrong, how to detect it, and how to keep the generated project aligned with the original. It intentionally avoids caching instructions so it stays focused on the core migration, while the blog captures the caching and benchmarking detail.

This is the part that compounds. Each migration adds new edges, new fixes, and a cleaner playbook for the next one. The agent does the work, but the skill makes the work repeatable.

## What we learned

Generated projects reward precision. Small mismatches in resource handling or source sets show up as runtime failures. Cache workflows are powerful, but they surface platform-specific issues that never appear in a basic iOS build. And keeping a migration close to the original is not a philosophical stance; it is a practical way to keep risk low and failures localized.

If this story reads like a sequence of obstacles, it is because real migrations are. But the pattern is clear. With a careful plan and a disciplined feedback loop, a coding agent can take a large production app, migrate it to Tuist generated projects, enable caching, and ship the outcome with benchmarks and documentation.

We are going to run this playbook again. Each time we do, the skill will get sharper, the edge cases will get smaller, and the speedups will become more predictable. That is the kind of progress that makes tooling adoption feel inevitable rather than risky.
