---
{
  "title": "Bazel cache and invocations",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Bazel cache entries and inspect completed Bazel invocations with Tuist."
}
---
# Bazel cache and invocations {#bazel-cache-and-invocations}

Tuist connects a Bazel project to the remote cache and reports completed commands through Bazel's [Build Event Protocol](https://bazel.build/remote/bep). The dashboard keeps the two kinds of data distinct: **Overview** shows remote-cache observations from Kura, while **Invocations** shows command outcome and duration with cache totals when Bazel supplied the same invocation identifier.

## Setup {#setup}

Create a project with Bazel as its build system, authenticate the Tuist command-line interface, and run this from the root of the Bazel repository:

```bash
tuist bazel setup
```

Add the generated file to your repository's `.bazelrc`:

```text
try-import %workspace%/.bazelrc.tuist
```

The generated configuration points both Bazel's [Remote Execution API](https://github.com/bazelbuild/remote-apis) cache and Build Event Service at Kura. It uses the existing Tuist credential helper for both connections.

Build Event Service uploads the complete event stream from the machine running Bazel. That stream can include command-line arguments, environment values, and command output. Kura retains only the completed-command fields documented below and discards the other events, but teams that do not want to transmit this telemetry can run `tuist bazel setup --no-build-insights` to configure only the remote cache.

Run a normal Bazel command to verify the integration:

```bash
bazel build //...
```

## Dashboard data {#dashboard-data}

The **Invocations** page records completed `build`, `test`, and other Bazel commands. It includes the command kind, success or failure status, exit code, start and finish time, and duration. The page also shows cache hits, misses, downloads, and uploads only for cache requests that Bazel attributed to that same invocation.

Cache activity can occur without a completed invocation, for example if Kura restarts while a command is running. Those observations remain visible on **Overview**, but they are not treated as evidence of command success, duration, or test results.

Tuist retains Bazel invocation and remote action-cache analytics for 90 days. See <.localized_link href="/guides/server/data-retention">data retention</.localized_link> for the full policy.
