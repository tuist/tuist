---
{
  "title": "Once project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect Once to Tuist for shared caching, live build and test insights, test sharding, and application previews."
}
---
# Once project {#once-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/once-project
```

:::

[Once](https://buildonce.dev) runs cacheable scripts and build graphs. Connect it to Tuist to share cached work across machines, follow runs live, and publish applications for your team to try. Keep your existing project sources and build definitions; the integration lives in `once.toml`.

## Prerequisites

- [Once](https://buildonce.dev/docs/guide/getting-started) installed and a workspace or cacheable script.
- A Tuist account. The Tuist CLI is not required for the Once integration.

## Connect the project {#connect-the-project}

From your repository root, run:

```bash
once connect --provider tuist --create
```

Once signs you in when needed, creates a Tuist project under your personal account, and writes the provider binding to `once.toml`. See [Connect a project](https://buildonce.dev/docs/guide/infrastructure/connect) to select another account or an existing project.

For an existing Tuist project, configure the provider and cache binding yourself:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

Replace `acme` and `app` with your account and project handles, then authenticate:

```bash
once auth login --provider tuist
```

Commit `once.toml` so your teammates and CI share the destination, not your credentials. Each developer signs in on their own machine.

## Shared cache

A local cache only helps the machine that populated it. With Tuist configured, Once can restore matching results produced by another developer or CI instead of running the same work again.

Run your cacheable script or a graph target as usual:

```bash
once build MyApplication
```

Open **Once Cache** in the dashboard to inspect remote cache activity. See <.localized_link href="/guides/features/cache/once">Once cache</.localized_link> for setup and a cross-machine reuse check.

## Build insights

Once prints a dashboard link as a run starts. Open it to follow the graph, action status, and cache decisions while the run progresses. Use **Builds** to compare local and CI performance and investigate failed actions. Keep CI logs for full process output; raw action log ingestion is not currently available.

See <.localized_link href="/guides/features/build-insights/once">Once build insights</.localized_link> for what is recorded and how to access it from coding agents or Grafana.

## Test insights and sharding

Run your Once test targets:

```bash
once test
```

Open **Tests** to inspect reported suites, cases, durations, and failures. Results depend on the test target's reporting capabilities; an action that runs a test process is not automatically a per-case test report.

When the suite outgrows one machine, create a hosted shard plan and distribute its batches across CI workers. See <.localized_link href="/guides/features/test-insights/once">Once test insights</.localized_link> and <.localized_link href="/guides/features/test-sharding/once">Once test sharding</.localized_link>.

## Previews and bundle size

Add an artifact binding to the same provider to publish supported Android, Apple simulator, and macOS applications:

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
once artifact publish MyApplication --track review
```

The returned link opens your project's previews; processing may take a moment. See <.localized_link href="/guides/features/previews/once">Once previews</.localized_link> for signing requirements and optional publication after builds.

To track bundle size, use the Tuist CLI separately against a built `.app`, `.ipa`, `.xcarchive`, `.apk`, or `.aab`. Follow the <.localized_link href="/guides/features/bundle-insights">Apple or Android bundle insights guide</.localized_link>; publishing a Once artifact does not automatically upload a bundle-size report.

## Continuous integration

Use an account token authorized for the project's operations in `TUIST_TOKEN`, or authenticate through a supported CI provider's OpenID Connect identity:

```bash
once auth login --provider tuist --no-browser
once build MyApplication
once test
```

On GitHub Actions, grant the job `id-token: write` and `contents: read`. Follow <.localized_link href="/guides/integrations/continuous-integration#once">Once on continuous integration</.localized_link> for an example. A personal developer login is not a CI credential.

## Remote execution

Accounts with remote execution enabled can also run eligible graph command actions on Tuist's Linux workers. This is separate from sharing cached results and from running an entire CI workflow. See <.localized_link href="/guides/features/runners/once">Once remote execution</.localized_link> for worker requirements and setup.
