---
{
  "title": "Struo remote execution",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Run eligible Struo graph command actions on Tuist's Linux remote execution workers."
}
---
# Struo remote execution {#struo-remote-execution}

<a id="once-remote-execution"></a>

Shared caching avoids repeating work that another machine has already completed. Remote execution also moves eligible cache misses off your computer: Struo schedules graph command actions on Tuist's single-use Linux workers and retrieves their outputs through the same project cache.

> [!NOTE]
> Remote execution is currently invite-only. [Contact us](mailto:contact@tuist.dev) to request access for your account.

> [!IMPORTANT]
> **Requirements**
>
> - A Tuist account with remote execution enabled and available execution capacity.
> - A Struo version with Tuist remote execution support.
> - A compatible server that advertises the worker image, cache endpoint, concurrency, and an absolute execution directory. Servers that omit the directory are not compatible with the current Struo client; Struo stops before uploading work.
> - Commands and toolchains that can run on `linux/amd64` inside the advertised worker image.

This runs graph actions, not an entire CI job. Configuring Struo does not install GitHub or GitLab workflow orchestration.

## Setup {#setup}

Complete <.localized_link href="/guides/get-started/struo-project">Get started with Struo</.localized_link>. Select the same Tuist provider for caching and execution, and pin the worker image advertised by the service:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
execution_image = "sha-REPLACE_WITH_THE_IMAGE_TAG"

[infrastructure.cache]
provider = "tuist"

[infrastructure.execution]
provider = "tuist"
```

Authenticate with credentials that can read and write the project's cache, then request remote execution:

```bash
struo build --remote MyTarget
```

Replace the target and image tag with your own. Struo checks the advertised image, execution directory, cache destination, and account capacity before uploading work. Cache and execution must point to the same project.

## Prepare actions for workers {#prepare-actions-for-workers}

- Declare inputs and outputs. Outputs must remain beneath the action's working directory.
- Resolve tools inside the worker image, not at absolute paths on the initiating computer.
- Use actions that are safe to repeat: a worker failure or service restart can cause another execution.
- Keep timeouts within the service's ten-minute action limit. Unsupported requirements, including network denial, fail rather than silently running locally.

Struo respects the account's advertised action concurrency and backs off when the service queue is full. Changing the image separates build configuration and cached results, preventing reuse across incompatible worker images.

## Inspect remote execution {#inspect-remote-execution}

The project sidebar has a **Remote execution** page. Its **Analytics** card shows the executions and total execution time of the selected period, as described in <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">Running actions and usage</.localized_link>. With Struo releases after 2.19.0, each remote action names the Struo run it belongs to, so the page also charts queue and execution times and lists runs with their remote actions, outcome and timings, running runs first. A run opens its page in **Build Runs**. Runs from older clients, and actions answered from the remote cache, are not counted there. The remote actions running and queued right now are available from the `get_remote_execution_activity` MCP tool and its REST endpoint. Both come from the execution service, not from worker lanes.

See [Struo's remote execution guide](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) for queueing, authentication refresh, and cache-endpoint overrides. Follow <.localized_link href="/guides/features/build-insights/struo">Struo build insights</.localized_link> to inspect the resulting runs.
