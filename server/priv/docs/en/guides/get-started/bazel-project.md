---
{
  "title": "Bazel project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Bazel workspace to Tuist for a shared remote cache and build and test insights across CI, without changing any BUILD file."
}
---
# Bazel project {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

Follow this path to plug an existing Bazel workspace into Tuist. Tuist exposes a [Remote Execution API](https://github.com/bazelbuild/remote-apis) cache that Bazel connects to as a remote cache, and a Build Event Service stream that turns every build and test into visible data on the dashboard.

Every section below opens with what's missing today and then walks you through the feature that fills the gap.

## Prerequisites

- A Bazel workspace (a `WORKSPACE` or `MODULE.bazel` at its root) and Bazel on your `PATH`.
- The <.localized_link href="/guides/install-tuist">Tuist command-line interface</.localized_link>.

## Connect the workspace

> [!NOTE]
> The Bazel workflow inside `tuist init` requires a version of the Tuist CLI that ships with it. On earlier releases, `tuist init` will not list "Integrate a Bazel workspace" as an option. Fall back to `tuist auth login` followed by `tuist bazel setup` from the workspace root, which walks through the same steps below.

From the root of the Bazel workspace, run `tuist init`. Tuist detects the `WORKSPACE` / `MODULE.bazel` and offers **Integrate a Bazel workspace**. Authenticate in the browser and pick the account that should own the project.

```bash
tuist init
```

If you're driving this from a coding agent or a script, run `tuist auth login` first (the browser flow waits for you to press Enter), then use the non-interactive form:

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

When init finishes, Tuist:

1. Writes a `tuist.toml` at the workspace root with the project handle.
2. Writes a `.bazelrc.tuist` next to your `.bazelrc`, wired to the closest Tuist cache region and authenticated through a per-workspace credential helper.
3. Adds a `try-import %workspace%/.bazelrc.tuist` line to your `.bazelrc`.

Commit the `try-import` line. It's identical on every machine. Add `.bazelrc.tuist` to your `.gitignore`. The credential-helper path is per-user and the cache region is per-location, so it should not be shared.

Everything below turns on automatically once the workspace is connected.

## Remote cache

Bazel's own local disk cache lives under `~/.cache/bazel` (or wherever `--disk_cache` points). A hit on one developer's machine doesn't reach anyone else, and CI job containers start from an empty cache every run.

Bazel's [Remote Execution API](https://github.com/bazelbuild/remote-apis) is the protocol for extending that same cache to a shared endpoint. Tuist speaks it. Once `.bazelrc.tuist` is in place, Bazel skips actions whose outputs are already in the shared cache and downloads them instead. One machine's work benefits every other machine building the same revision.

Verify with two clean builds against the same revision (locally, or one local + one CI):

```bash
bazel clean
bazel build //...
```

The second run's summary should report cache hits. Open **Cache** on the dashboard to see hit rates over time.

## Build and test insights

Bazel's build event stream and per-test XML reports are emitted per invocation. Comparing target-level durations across a week, or spotting a test that has become flaky over several CI runs, means collecting and aggregating those events somewhere.

The Build Event Service protocol Bazel already emits is designed for exactly that. The `.bazelrc.tuist` that `tuist init` wrote configures the BES stream against Tuist, so build and test insights start flowing on the next `bazel build` and `bazel test`. Nothing extra to configure. Open **Builds** and **Tests** on the dashboard to see the data.

## Bring the team along

Cache hits and insights compound with the number of people connected to the project. Invite your teammates to the organization from the account settings on the dashboard, and set up <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) so onboarding is a click rather than a per-person `tuist auth login`.
