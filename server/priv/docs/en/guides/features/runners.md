---
{
  "title": "Runners",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Run your GitHub Actions jobs on Tuist-managed macOS and Linux runners with a cache colocated next to the compute and shared with your local machines."
}
---
# Runners {#runners}

> [!IMPORTANT]
> **Invite-only**
>
> Tuist Runners are currently invite-only while we scale capacity. [Reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access for your account.


Tuist Runners are managed macOS and Linux runners for your GitHub Actions workflows. Instead of running jobs on GitHub-hosted runners, you point `runs-on` at a Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> and your jobs run on Tuist's fleet, next to the same <.localized_link href="/guides/features/cache">cache</.localized_link> your team already uses.

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link>
> - Your project connected to a <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> organization


## Why Tuist Runners {#why-tuist-runners}

Most CI runner providers make jobs faster by giving you beefier machines and a persistent cache — typically a shared volume mounted back into your CI runs. That helps, but a volume is just a disk: it carries whatever previous CI runs happened to leave on it. It isn't replicated to keep just the freshest artifacts close to where builds run, and it never reaches your developers' machines.

Tuist Runners are different because the cache is the same cache your developers and every other environment already read from and write to. The <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> and <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache</.localized_link> that a teammate warms on their laptop, or that an earlier build produced, are a hit on the runner — and vice versa. There's no separate CI cache to warm up.

On top of that, the cache runs on the same private network as the runner. When a job lands on a fleet colocated with your cache, Tuist hands it an in-cluster cache endpoint (`TUIST_CACHE_ENDPOINT`), so cache reads and writes stay on the internal network next to the compute instead of crossing the public internet.

Put together:

- **Shared with local environments.** The runner reads and writes the same cache as `tuist` and Xcode on developer machines. Work done anywhere warms the cache everywhere. You can bring the same cache even closer to CI, offices, or regional compute by <.localized_link href="/guides/features/cache/self-hosting">self-hosting cache nodes</.localized_link>.
- **Colocated with the compute.** Cache traffic stays on the internal network next to the runner, not over a public ingress.
- **One system, not bolted-on.** Cache, <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link>, <.localized_link href="/guides/features/test-sharding">test sharding</.localized_link>, and <.localized_link href="/guides/features/build-insights">build insights</.localized_link> all run against the same project and account, so the runner isn't a separate silo of build data.

## Getting started {#getting-started}

1. **Request access.** Runners are invite-only during the beta. [Reach out](mailto:contact@tuist.dev) with the account you want enabled.
2. **Connect GitHub.** Make sure your <.localized_link href="/guides/server/accounts-and-projects">project</.localized_link> is connected to your <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> organization. Tuist receives `workflow_job` events for that organization and dispatches matching jobs to the fleet.
3. **Point `runs-on` at a Tuist profile.** Every enabled account starts with two ready-to-use <.localized_link href="/guides/features/runners/profiles">profiles</.localized_link>: `linux` and `macos`. Reference them with the `tuist-` prefix:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

4. **Push and watch.** The job is queued, claimed by a runner, and streamed back to the **Runners** section of your Tuist dashboard, where you can follow its logs, steps, and machine metrics.

That's it — no runner agent to install, no self-hosted infrastructure to maintain. Tuist mints a short-lived, single-use [just-in-time runner token](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/configure-the-application) for each job, so nothing long-lived is registered with your repository.

## Platforms and machine shapes {#platforms-and-machine-shapes}

Runners are available on macOS (Apple silicon, virtualized on the Mac fleet) and Linux. Each <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> pins a machine shape — a `(vCPUs, memory)` pair — from the catalog below.

### Linux {#linux}

| vCPUs | Memory |
| ----- | ------ |
| 1     | 2 GB   |
| 2     | 4 GB   |
| 2     | 8 GB (default) |
| 4     | 8 GB   |
| 4     | 16 GB  |
| 8     | 16 GB  |
| 8     | 32 GB  |
| 16    | 32 GB  |

### macOS {#macos}

| vCPUs | Memory |
| ----- | ------ |
| 6     | 14 GB (default) |

macOS profiles also pin an **Xcode version**. The version selects a runner image with that Xcode preinstalled, so jobs start with the toolchain already in place. Supported versions today:

- `26.5` (default)
- `26.4.1`
- `26.3`
- `26.0.1`

> [!NOTE]
> The catalog evolves as we add hardware and Xcode releases. The **New profile** form in the dashboard always shows the shapes and Xcode versions currently available to your account, so treat it as the source of truth.

## Observability {#observability}

Every job dispatched to the fleet shows up in the **Runners** section of your account, grouped by workflow. For each job you get:

- **Live logs**, pulled from the GitHub Actions logs API and searchable after the run.
- **Step timing**, so you can see which steps dominate a job.
- **Machine metrics** — CPU, memory, and disk sampled over the job's lifetime — to right-size the <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> you run on.

Because runs are attributed to the same project as the rest of your Tuist data, they sit alongside your <.localized_link href="/guides/features/build-insights">build insights</.localized_link> and <.localized_link href="/guides/features/test-insights">test insights</.localized_link> rather than in a separate tool.

## Profiles {#profiles}

A **profile** is a named alias for a machine shape that you reference from `runs-on`. Profiles are how you choose Linux vs. macOS, pick a size, and pin an Xcode version — without hardcoding infrastructure details in every workflow file.

<.localized_link href="/guides/features/runners/profiles">Learn how to create and manage profiles →</.localized_link>
