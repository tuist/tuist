---
{
  "title": "Gradle project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Gradle project to Tuist for a shared remote build cache, build and test insights across CI, bundle-size tracking, and preview links."
}
---
# Gradle project {#gradle-project}

> [!TIP]
> **Rather have a coding agent do this?**
>
> Give this to a coding agent:
>
> ```text
> Follow the setup at
> https://tuist.dev/en/docs/guides/get-started/gradle-project
> ```

Follow this path to point an existing Gradle project at Tuist. The `dev.tuist` Gradle plugin wires Gradle's local build cache to Tuist's remote cache and uploads build and test data to the dashboard, without changing a single `./gradlew` command.

Every section below opens with what's missing today and then walks you through the feature that fills the gap.

## Prerequisites

- A Gradle project with a `settings.gradle.kts` (or `settings.gradle`).
- The <.localized_link href="/guides/install-tuist">Tuist command-line interface</.localized_link>.

## Connect the project

From the root of the Gradle project, run `tuist init`. Choose **Integrate a Gradle project**, then authenticate in the browser and pick the account that should own the project.

```bash
tuist init
```

If you're driving this from a coding agent or a script, run `tuist auth login` first (the browser flow waits for you to press Enter), then use the non-interactive form:

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist writes a `tuist.toml` at the repository root with the project handle and prints a `plugins { ... }` block. Paste it at the top of `settings.gradle.kts`:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

Sanity-check with `./gradlew help`. Gradle should load without errors. If it can't find the plugin, make sure the block is in `settings.gradle.kts`, not `build.gradle.kts`.

Everything below is optional and independent.

## Remote build cache

Gradle's local build cache stores task outputs on the machine that produced them. Two developers on the same branch hit the cache in their own `~/.gradle` and not each other's, and CI hits a fresh, empty cache every job.

The Tuist remote cache extends the same key/value protocol Gradle already uses across machines. A task's outputs are uploaded on the machine that first executed it and downloaded by anyone else that comes across the same inputs. Enable it in `gradle.properties`:

```properties
org.gradle.caching=true
```

Then build in two environments:

```bash
./gradlew clean build --build-cache --info
```

Cacheable tasks report `FROM-CACHE` on the second run. Open **Cache** on the dashboard to see hit rates over time.

## Build insights

Gradle emits task timings at the end of a build, and with `--profile` writes a per-build HTML report. Neither aggregates across runs. A task that has gotten slower over a series of commits looks the same on any single build's report as it always did.

The `dev.tuist` plugin uploads task timings for every build to the dashboard automatically once the plugin is applied. There's nothing extra to configure. Open **Builds** on the dashboard after your next `./gradlew build` to see the trend.

## Test insights

Gradle's test reports live per-build under `build/reports/tests/`. A test that fails intermittently across ten CI runs looks, in any given report, like a stable test that happened to fail once.

Test insights records every task's outcome and duration for every `./gradlew test` run and correlates results across runs. Flaky tests, slow tests, and failures surface on the dashboard's **Tests** tab. When flakes accumulate, quarantine them from the dashboard so they stop blocking merges.

The plugin also supports a **stress-testing mode** that reruns test cases a build introduces and flags any that prove flaky before they land. Add it to the `tuist` extension in `settings.gradle.kts`:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## Bundle insights

The Android Gradle Plugin reports the size of the produced `.aab` in the build output. That number disappears with the branch, and comparing sizes across releases is a manual accounting job. Play Console reports the same numbers, but only after the artifact has been uploaded.

Bundle insights records install and download sizes for every `.aab` (recommended) or `.apk` and can fail a PR check when a per-branch threshold is breached. Add this to your CI right after your build step:

```bash
tuist inspect bundle App.aab
```

Open **Bundle insights → Android** on the dashboard to see the trend and configure thresholds.

## Previews

Play Console's internal test track adds a review-and-propagation delay on every share. Sending a raw `.apk` through Slack or email is faster but loses track of which build a specific message refers to.

Previews turns a build into a shareable link that recipients install with one command:

```bash
tuist share App.apk
```

## Bring the team along

Cache hits, insights, and stress-testing all compound with the number of people connected to the project. Invite your teammates to the organization from the account settings on the dashboard, and set up <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) so onboarding is a click rather than a per-person `tuist auth login`.

For CI, don't use a personal login. Set `TUIST_TOKEN` scoped to your project (create it from the project settings on the dashboard).

## Full plugin reference

Everything covered here is the minimum to get value out of Tuist on a Gradle project. Configuration options for the `tuist` extension block, `stressNewTests` mode, and CI authentication live in the [Install the Gradle plugin](https://tuist.dev/en/docs/guides/install-gradle-plugin) reference.
