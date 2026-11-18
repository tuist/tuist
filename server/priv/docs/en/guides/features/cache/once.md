---
{
  "title": "Once cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Once action results across developer machines and CI with Tuist's remote cache."
}
---
# Once cache {#once-cache}

Once can reuse results locally, but a developer's local cache does not reach their teammates or a fresh CI worker. Tuist provides a shared remote cache so matching work only needs to run on one machine.

## Setup {#setup}

Complete <.localized_link href="/guides/get-started/once-project#connect-the-project">Get started with Once</.localized_link>, then check the cache binding in your repository's `once.toml`:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

Authenticate with `once auth login --provider tuist`. No Tuist executable or additional cache plugin is required. The same provider supports [cacheable scripts](https://buildonce.dev/docs/guide/scripted/caching) and [graph targets](https://buildonce.dev/docs/guide/graph).

Only work declared cacheable by Once can be reused. Declare the inputs, outputs, and environment the work depends on; configuring a remote cache does not make an arbitrary command reproducible.

## Verify shared reuse {#verify-shared-reuse}

Run the same cacheable script or graph target on two machines with matching inputs and configuration:

```bash
once build MyApplication
```

The first machine populates the shared cache. On a second machine whose local cache has not seen that result, a hit and restored outputs confirm remote reuse. Repeating the command on the first machine alone can demonstrate a local hit, not that Tuist supplied the result.

## Inspect cache activity {#inspect-cache-activity}

Open **Once Cache** in your Tuist project to inspect action-cache hits, transfers, latency, and throughput. Open a run's **Cache** view to inspect its reported action decisions and content-object activity.

Action results and content objects answer different questions: a missing action result means Once must do the work, while a content-object request transfers an input or output. Do not treat a blob download as an executed action or an action-cache hit.

For the run's action graph and structured errors, see <.localized_link href="/guides/features/build-insights/once">Once build insights</.localized_link>.

## Continuous integration {#continuous-integration}

Use `TUIST_TOKEN` or Once's headless OIDC login, as described in <.localized_link href="/guides/integrations/continuous-integration#once">Once on continuous integration</.localized_link>. Keep credentials out of `once.toml`.

The account's <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">cache upload policy</.localized_link> determines who can publish results. A read-only developer can consume CI-produced entries without becoming a cache writer.

See [Once's Tuist integration](https://buildonce.dev/docs/guide/infrastructure/tuist#connection-recovery) for connection retries and troubleshooting. Retries do not make interrupted uploads resumable.
