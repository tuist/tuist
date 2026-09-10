---
{
  "title": "Bazel cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Bazel remote cache entries across your team and CI with Tuist."
}
---
# Bazel cache {#bazel-cache}

Tuist exposes a [Remote Execution API](https://github.com/bazelbuild/remote-apis) cache that Bazel connects to as a remote cache. When an action's outputs are already in the cache, Bazel skips the action and pulls the result from Tuist's cache, saving compilation time across your team and CI environments.

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link> with Bazel selected as the build system
> - The Tuist command-line interface, authenticated with `tuist auth login`

## Setup {#setup}

From the root of the Bazel workspace, run:

```bash
tuist bazel setup
```

This writes a `.bazelrc.tuist` file next to your `.bazelrc`, wired to the closest Tuist cache region and authenticated through a per-workspace credential helper. It also adds a `try-import` line to your repository's `.bazelrc`:

```text
try-import %workspace%/.bazelrc.tuist
```

Pass `--no-add-bazelrc-import` if you want to manage the import yourself. The generated file is safe to check in.

Setup leaves an existing `.bazelrc` alone when it cannot find a Bazel workspace marker, when the file is a symbolic link, or when it already configures a remote cache or Build Event Service. That way, running it again is idempotent.

Run a normal Bazel command to verify the integration:

```bash
bazel build //...
```

Cache activity then appears on the project's **Overview** page in the Tuist dashboard, broken down by action-cache and content-addressable-storage operations.

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
