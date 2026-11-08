---
{
  "title": "Once remote execution",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Run eligible Once graph command actions on Tuist's Linux remote execution workers."
}
---
# Once remote execution {#once-remote-execution}

Shared caching avoids repeating work that another machine has already completed. Remote execution also moves eligible cache misses off your computer: Once schedules graph command actions on Tuist's single-use Linux workers and retrieves their outputs through the same project cache.

> [!IMPORTANT]
> **Requirements**
>
> - A Tuist account with remote execution enabled and available execution capacity.
> - A Once version with Tuist remote execution support.
> - A compatible server that advertises the worker image, cache endpoint, concurrency, and an absolute execution directory. Servers that omit the directory are not compatible with the current Once client; Once stops before uploading work.
> - Commands and toolchains that can run on `linux/amd64` inside the advertised worker image.

This runs graph actions, not an entire CI job. Configuring Once does not install GitHub or GitLab workflow orchestration.

## Setup {#setup}

Complete <.localized_link href="/guides/get-started/once-project">Get started with Once</.localized_link>. Select the same Tuist provider for caching and execution, and pin the worker image advertised by the service:

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
once build --remote MyTarget
```

Replace the target and image tag with your own. Once checks the advertised image, execution directory, cache destination, and account capacity before uploading work. Cache and execution must point to the same project.

## Prepare actions for workers {#prepare-actions-for-workers}

- Declare inputs and outputs. Outputs must remain beneath the action's working directory.
- Resolve tools inside the worker image, not at absolute paths on the initiating computer.
- Use actions that are safe to repeat: a worker failure or service restart can cause another execution.
- Keep timeouts within the service's ten-minute action limit. Unsupported requirements, including network denial, fail rather than silently running locally.

Once respects the account's advertised action concurrency and backs off when the service queue is full. Changing the image separates build configuration and cached results, preventing reuse across incompatible worker images.

See [Once's remote execution guide](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) for queueing, authentication refresh, and cache-endpoint overrides. Follow <.localized_link href="/guides/features/build-insights/once">Once build insights</.localized_link> to inspect the resulting runs.
