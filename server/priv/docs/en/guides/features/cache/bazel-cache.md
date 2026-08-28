---
{
  "title": "Bazel cache and invocations",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Bazel cache entries and inspect completed Bazel invocations with Tuist."
}
---
# Bazel cache and invocations {#bazel-cache-and-invocations}

Tuist connects a Bazel project to the remote cache and records completed commands directly from the Tuist command-line interface. The dashboard keeps the two kinds of data distinct: **Overview** shows remote-cache observations from Kura, while the **Builds** and **Tests** pages show command outcome and duration with cache totals when Bazel supplied the same invocation identifier.

## Setup {#setup}

Create a project with Bazel as its build system, authenticate the Tuist command-line interface, and run this from the root of the Bazel repository:

```bash
tuist bazel setup
```

Add the generated file to your repository's `.bazelrc`:

```text
try-import %workspace%/.bazelrc.tuist
```

The generated configuration points Bazel's [Remote Execution API](https://github.com/bazelbuild/remote-apis) cache at Kura. It uses the existing Tuist credential helper for that cache connection.

Run Bazel through Tuist to verify the integration and upload its [Build Event Protocol](https://bazel.build/remote/bep) output directly to Tuist:

```bash
tuist bazel invoke build //...
```

## Dashboard data {#dashboard-data}

The **Builds** page records completed `bazel build` work, and **Tests** records final test targets reported by `bazel test` and `bazel coverage`. Build rows include the requested Bazel target patterns, while test rows include the reported test target. They also include status, start and finish time, duration, and cache totals only when Bazel supplied the same invocation identifier. The invocation detail page has **Overview**, **Cache**, and **Logs** tabs. It keeps the requested command compact and lets developers expand sanitized configuration facts: Bazel version, active named configurations, compilation mode, and whether remote cache or remote execution were enabled. It never stores or shows raw argument values, local paths, client environment variables, or credentials. The **Logs** tab and download action contain up to 10 megabytes of Bazel standard output and standard error. The **Cache** page shows the corresponding action-cache hit rate per invocation, along with the observed activity.

Kura currently emits measurements for action-cache requests. Its action-cache transfer is the serialized action-cache response or update, and its latency is the time Kura spent handling that request. Throughput is derived from those bytes and measured duration, excluding requests whose duration rounds to zero milliseconds. These are not whole-remote-cache artifact-transfer metrics: Tuist does not yet attribute content-addressed artifact reads and writes to a Bazel invocation.

Cache activity can occur without a completed invocation, for example if Kura restarts while a command is running. Those observations remain visible on **Overview**, but they are not treated as evidence of command success, duration, or test results.

Tuist retains Bazel invocation and remote action-cache analytics for 90 days. See <.localized_link href="/guides/server/data-retention">data retention</.localized_link> for the full policy.
