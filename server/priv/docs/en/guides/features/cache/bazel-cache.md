---
{
  "title": "Bazel cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Bazel remote cache entries across your team and CI with Tuist."
}
---
# Bazel cache {#bazel-cache}

Tuist exposes a [Remote Execution API](https://github.com/bazelbuild/remote-apis) cache that Bazel connects to as a remote cache. When an action's outputs are already in the cache, Bazel skips the action and pulls the result from Tuist's cache, saving compilation time across your team and CI environments. For a GitHub Actions setup, see [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions). For how remote caching works and how self-hosted and managed caches compare, see [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache).

## Setup {#setup}

From the root of the Bazel workspace, run:

```bash
tuist bazel setup
```

This writes a `.bazelrc.tuist` file next to your `.bazelrc`, wired to the closest Tuist cache region and authenticated through a per-workspace credential helper. It also adds a `try-import` line to your repository's `.bazelrc`:

```text
try-import %workspace%/.bazelrc.tuist
```

Pass `--no-add-bazelrc-import` if you want to manage the import yourself.

Add `.bazelrc.tuist` to your `.gitignore` and run setup on each machine instead of committing it. The generated file points at an absolute credential-helper path under the current user's Tuist configuration directory and at the cache region closest to the machine that generated it, so neither value transfers to a teammate or a continuous integration runner. Commit the `try-import` line in `.bazelrc`, which is the same on every machine.

Setup leaves an existing `.bazelrc` alone when it cannot find a Bazel workspace marker, when the file is a symbolic link, or when it already configures a remote cache or Build Event Service. That way, running it again is idempotent.

Run a normal Bazel command to verify the integration:

```bash
bazel build //...
```

Cache activity then appears on the project's **Bazel Cache** page in the Tuist dashboard, which shows cache transfer, downloads and uploads, read and write latency, throughput, and the action-cache hit rate. The project **Overview** carries a summary of the same action-cache hit rate alongside build duration.

To see how one command used the cache, open it from **Invocations**. The invocation page separates action-cache lookups from content-object requests, so you can tell a cold action cache apart from a slow artifact download.

## Remote execution {#remote-execution}

Tuist can also run your Bazel actions on its Linux executors, so cache misses run remotely instead of on the local machine or CI runner. Remote execution is available for enabled accounts; [email us](mailto:contact@tuist.dev) or [book a call](https://cal.tuist.dev/team/tuist/tuist) to enable it for yours. Then pass `--remote-execution` to setup:

```bash
tuist bazel setup --remote-execution
```

Setup then points Bazel at Tuist's executor in `.bazelrc.tuist`, next to the remote cache. It looks up the current executor and image each time it runs, so rerun setup rather than copying the generated values. Actions run with the executor's Linux toolchain, not the tools installed on your machine, so declare the toolchains your actions need in the workspace.

Setup also sets `--jobs` to twice the number of remote actions your account can run at once, so each one has the next action waiting. Without that, Bazel runs as many actions in parallel as the machine has cores, and a 2-core CI runner keeps only two remote actions in flight.

To use a different value, pass `--jobs` on the command line, or set it in `.bazelrc` after the `try-import` line. Bazel uses the last value it reads, so a `--jobs` before that line is replaced by the generated one.

### Executor sizes {#executor-sizes}

Actions use 4 GB of memory and 2 vCPUs by default. Set the `tuist-memory-gb` execution property to request a smaller or larger VM:

| `tuist-memory-gb` | Memory | vCPUs | Workspace disk |
| --- | --- | --- | --- |
| `2` | 2 GB | 1 | 30 GB |
| `4` (default) | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

For example, add this **after** the `try-import` line in `.bazelrc` to request 8 GB by default:

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

For one target, use `exec_properties = {"tuist-memory-gb": "8"}` in its Bazel rule instead. Only `2`, `4`, `8` and `16` are supported. `2` runs twice as many actions at once within the same limits, but large compiler and linker steps can run out of memory in it; set those targets back to `4` or more. Larger actions consume proportionately more of the account's allocated vCPU and memory limits, reducing how many can run simultaneously. A shape must fit both limits. The generated `--jobs` uses the default shape; override it if needed when requesting larger shapes.

Executors currently use Tuist's Linux amd64 image. Arbitrary container images, other execution operating systems and architectures, persistent action workers and bring-your-own executors are not configurable through setup. Rerun setup to obtain the current image and endpoint.

### Running actions and usage {#running-actions-and-usage}

The project's **Remote execution** page shows what runs now and what has run:

- **Invocations** lists running Bazel invocations first, refreshed every five seconds, with how long each has run and how many of its remote actions are running and queued. An invocation appears once Kura has its target patterns and stays until its completed report arrives. Opening one shows its **Executions**: first its remote actions that are executing in a VM or waiting for one, then the 50 that finished most recently with their result (Passed, Cached, Failed or Error), each with its mnemonic, target, machine size and duration so far. An action that has just finished shows as **Finishing** for up to a minute until its record arrives. Every row opens the action's page; while the action still runs, the page shows its status, machine and digest, and loads the full record once it finishes. Actions the execution gateway runs on a VM it prepared in advance are not listed while they run; they appear among the finished ones. Running invocations are not shown while you search or filter the list.
- **Analytics** starts with **Executions** and **Total execution time** for the selected period, with changes since the previous period and a chart over time. Total execution time is how long each action's executor ran in its VM, including fetching inputs and uploading outputs but not queueing or preparing the VM. It is the time the **Usage** page bills. Results served from the cache are not executions.

The same data is available from `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` and `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage` (optional `from` and `to`, defaulting to the last 30 days and spanning at most 366), and from the `get_remote_execution_activity` and `get_remote_execution_usage` MCP tools.

### Remote action timings {#remote-action-timings}

The rest of **Analytics** and the **Invocations** table cover actions with recorded remote phases: average and p50/p90/p99 queue and execution times with changes since the previous period, trend charts, and links to each invocation's phase timings. Filter by date (up to 90 days). The invocations table shows each invocation's average, p50 and p90 execution time. Search it by command, target or invocation ID, filter by status, command, targets or number of remote actions, and sort by any column except Invocation. Search and table filters apply only to the invocations table, not the analytics.

Open an invocation's **Remote execution** tab for its **Executions**, its remote actions sorted by duration (longest first) or by start time: one row per remote action with when it started relative to the profile, its duration and a bar split into queue, input-fetch, execution and output-upload time, scaled to the longest action on the page. Hover a bar for each phase's duration. The table uses uploaded Bazel profiles and associates server phases only with an unambiguous action on the same profile thread.

Missing timings mean **Not recorded**, not zero. Older profiles, missing action intervals and short phases omitted by Bazel may leave the table empty even when remote work occurred. Recorded retries are summed within each action. Server metadata can describe a cached result, so these timings are neither proof of fresh execution nor billable usage. Client input uploads and uploads of locally executed outputs are excluded from output-upload time.

The same data is available from the build-step REST endpoint with `remote_execution=true` and the `list_bazel_build_steps` / `get_bazel_build_step` MCP tools. Timings are retained for 90 days with the profile steps.

### Inspect a remote action {#inspect-a-remote-action}

When Tuist's executor records an action, its row in the invocation's **Remote execution** tab links to the action's page. **Overview** shows the status and exit code, queue, input-fetch, execution and output-upload times, whether the action was scheduled or ran on a worker leased for the invocation, the worker, memory, timeout and action digest. A failed action also gets an **Errors** card: compiler errors recognised in its standard error (Clang, GCC, Swift, javac, Go and rustc formats) grouped by file, or its exit code and the end of its standard error when none are recognised. **Logs** shows standard output followed by standard error in one log with line numbers, highlighting error lines. Like a CI job log it opens at the end, and **Load earlier lines** pages back. A record keeps the first 16 KiB of each stream; the executor also stores a longer stream whole as a run artifact, so the log and the **Errors** card cover all of the output. A stream over 16 MiB keeps only its first 16 KiB and last 16 MiB. A marker in the log shows where bytes are missing and why: skipped from a very long stream, or not stored, for example once the copy has expired. The **Command** card on **Overview** shows the command line, which **Copy** copies, the working directory and output paths, and the environment and platform properties in collapsed sections.

Environment variables whose names contain `TOKEN`, `SECRET`, `PASSWORD` or `KEY`, and the values of flags named that way, are shown as `****`. Records are best effort: a row without a link means no record matched its output unambiguously, not that the action ran locally. Records are kept for 90 days. The REST endpoints `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations/{invocation_id}/remote-actions` and `.../remote-actions/{operation_id}` and the `list_bazel_remote_actions` / `get_bazel_remote_action` MCP tools return the same records; `.../remote-actions/{operation_id}/logs/{stdout|stderr}` and `get_bazel_remote_action_log` read the logs by byte range. Stored log copies are run artifacts and expire with the plan's run-artifact window.

## Build insights {#build-insights}

By default, `tuist bazel setup` also configures Bazel's Build Event Service so completed commands appear on the **Invocations** dashboard. See <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> for what the dashboard shows and how to attach custom metadata.

If you only want the remote cache and would rather not send the build-event stream, opt out with:

```bash
tuist bazel setup --no-build-insights
```

## Continuous integration {#continuous-integration}

Authenticate CI with one of the methods in the <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link>, then run `tuist bazel setup` once as part of the checkout step so `.bazelrc.tuist` reflects the right region for the runner. See the <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> for provider-specific examples.

## Data retention {#data-retention}

Tuist keeps remote cache observations for 90 days. See <.localized_link href="/guides/server/data-retention">data retention</.localized_link> for the full policy.
