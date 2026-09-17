---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Compress a modular Xcode project into declarative Swift and unlock module caching, selective testing, a package registry, and build and test insights on top of the graph."
}
---
# Generated Xcode project {#generated-xcode-project}

> [!TIP]
> **Rather have a coding agent do this?**
>
> Give this to a coding agent:
>
> ```text
> Follow the setup at
> https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
> ```

Follow this path when you want Tuist to describe and generate your Xcode project from Swift manifests. A generated project compresses the complexity of a modular Xcode project into a concise, declarative description of the graph. It's also a strict requirement for the module cache and selective testing.

Every section below opens with what's missing today and then walks you through the feature that fills the gap.

## Prerequisites

- macOS with Xcode installed.
- The <.localized_link href="/guides/install-tuist">Tuist command-line interface</.localized_link>.

## Create the project (once)

The fastest way to see it working is a fresh project. In an empty directory, run `tuist init` and choose **Create a generated project**, pick the platform, confirm the name, then authenticate and pick the account that should own the project.

```bash
mkdir MyApp && cd MyApp
tuist init
```

When init finishes, run `tuist generate`. Tuist writes an `.xcworkspace` next to your manifests and opens it in Xcode. Build and run the target. You should see the example app launch in the simulator.

That's the "connected + generating" state. Everything below is optional and independent.

If you're moving an existing app, connect it first with the [Xcode project migration guide](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project), then come back and continue with the sections that fit your problem.

## Project generation

An `.xcodeproj` bundles the shape of your app into XML: file references, build phases, target dependencies, schemes, and build settings all live in the same tree, with no primitive for reasoning about the graph as a graph. As the project grows, that shape gets harder to hold in your head, and Xcode has no stable handle for tools to hash it and skip work when nothing changed.

Generated projects compress the graph into declarative Swift. `Project.swift` describes targets, dependencies, and resources directly, and Tuist keeps a stable model of the graph behind it. That model is what unlocks the sections below: module caching hashes it to reuse binaries, and selective testing hashes it to skip tests whose inputs haven't changed.

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            sources: ["MyApp/Sources/**"],
            dependencies: []
        )
    ]
)
```

Each `tuist generate` produces a deterministic workspace from the manifests. Add `.xcodeproj` and `.xcworkspace` to `.gitignore`.

## Module cache

Compiling a modular Xcode project from scratch is a per-machine cost. Each teammate and each CI runner produces its own copy of the same object files. The Xcode compilation cache shortens the inner loop but doesn't remove the per-machine build of every target, and it can't replace a whole framework with a prebuilt binary.

The module cache does. It builds every cacheable dependency in your graph once (frameworks, libraries, bundles), stores the resulting binaries against a hash of the target's inputs, and swaps the target for its binary on subsequent generations. Unchanged modules stop being compiled:

```bash
tuist cache
```

The first run compiles everything and uploads the binaries to your account. On the next `tuist generate`, unchanged dependencies are replaced with their cached binaries and Xcode links against `.xcframework`s instead of compiling from source.

## Selective testing

`xcodebuild test` doesn't know which tests a change touches, so CI runs the whole suite on every push. As the suite grows, the gap between what actually needs to run and what runs stretches from minutes to tens of minutes.

Selective testing runs only the tests affected by what changed since the last successful test run, using the project graph and the same hashing algorithm the module cache relies on:

```bash
tuist test
```

The first `tuist test` runs everything and persists per-target hashes. Subsequent runs skip targets whose inputs haven't changed. Move `tuist test` into CI in place of `xcodebuild test` and feedback lands in seconds instead of minutes.

## Package registry

Swift Package Manager resolves dependencies by deep-cloning each package's git history, because packages are addressed by URL rather than by a registry. On a project with dozens of transitive packages, resolution runs into minutes on a clean checkout and repeats on every CI job.

The Tuist Package Registry serves the same packages the Swift Package Index tracks, but as a real registry so SwiftPM only fetches the commit you actually need. Enable it once by setting `registryEnabled: true` in your `Tuist.swift`:

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

Regenerate. Package resolution drops from minutes to seconds.

## Build insights

Xcode records per-target build durations in the log and in the build report. Neither is aggregated across runs or across machines, so a build-time regression usually surfaces only as slower CI overall.

Build insights records every build's duration and phase timings for generated schemes automatically. There's nothing extra to configure. Open the dashboard's **Builds** tab after your next `tuist generate` + build cycle.

## Test insights

Xcode reports per-test results one run at a time. Cross-run signal — flakiness rate, week-over-week duration, which simulator variants fail — is not something Xcode aggregates.

Test insights records every test's outcome and duration for generated schemes automatically and correlates results across runs. Flaky tests, slow tests, and failures show up on the dashboard's **Tests** tab. When flakes accumulate, quarantine them from the dashboard so they stop blocking merges.

## Bring the team along

The module cache and selective testing pay off most when everyone is hitting the same shared surface. Invite your teammates to the organization from the account settings on the dashboard, and set up <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) so onboarding is a click rather than a per-person `tuist auth login`.
