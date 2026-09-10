---
{
  "title": "Bazel Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Bazel command duration, cache totals, and critical-path diagnostics in the Tuist dashboard."
}
---
# Bazel build insights {#bazel-build-insights}

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link> with Bazel selected as the build system
> - `tuist bazel setup` has been run in the workspace (see <.localized_link href="/guides/features/cache/bazel-cache">Bazel cache</.localized_link>)

Every completed `build`, `test`, and other Bazel command shows up on the project's **Invocations** dashboard: command kind, exit status, start and finish time, duration, and the cache hits, misses, downloads, and uploads that Bazel attributed to that same invocation.

Invocation data is delivered through Bazel's [Build Event Protocol](https://bazel.build/remote/bep). Setup wires it in for you when you run `tuist bazel setup`; no extra flags are required to start seeing invocations.

## What the dashboard shows {#what-the-dashboard-shows}

Each invocation records:

- The command Bazel ran, its exit code, start and finish time, and total duration.
- Action, target, and package counts.
- A bounded build timeline and critical-path summary.
- Cache hits, misses, downloads, and uploads attributed to the invocation.
- Progress-log lines captured during the run, in execution order.
- The Bazel version, the git branch and commit when Bazel reports them, and whether the run happened on CI.

Cache activity that Bazel cannot attribute to a completed invocation, for example when a command is interrupted mid-run, still appears on the project **Overview** as a raw remote-cache observation. It is not treated as evidence of command success, duration, or test results.

## Custom metadata {#custom-metadata}

Attach key-value data to invocations to compare runs from different teams, hardware, or workflows. Values appear on each invocation's detail page and through the application programming interface and Model Context Protocol tools.

Set metadata with Bazel's built-in `--build_metadata` flag:

```bash
bazel build --build_metadata=TICKET=TUIST-123 --build_metadata=RUNNER=macos-14 //...
```

Or set them once per lane in your `.bazelrc`:

```text
build:ci --build_metadata=RUNNER=macos-14
```

Each invocation can carry up to 20 custom entries. Keys can contain up to 50 characters and values up to 500 characters. Entries that exceed those bounds are dropped before the invocation is stored, so an invalid entry does not prevent the rest of the report from being recorded.

Context keys that Tuist derives from the build environment, such as `CI`, `GIT_BRANCH`, and `GIT_COMMIT`, are not stored as custom values because they already populate first-class fields on the invocation.

Custom metadata is visible to project members in the dashboard and through the application programming interface and Model Context Protocol tools. Do not use it for credentials, access tokens, or other sensitive data.

## Opting out {#opting-out}

The Build Event Protocol stream carries command-line arguments, environment values, and command output. Tuist only keeps the completed-command fields listed above and discards the rest, but if you would rather not send the event stream at all, re-run setup with:

```bash
tuist bazel setup --no-build-insights
```

The generated `.bazelrc.tuist` then configures only the remote cache. Invocations stop showing up in the dashboard, and cache observations remain on the **Overview** page.

## Data retention {#data-retention}

Tuist retains Bazel invocations and their logs for 90 days. See <.localized_link href="/guides/server/data-retention">data retention</.localized_link> for the full policy.
