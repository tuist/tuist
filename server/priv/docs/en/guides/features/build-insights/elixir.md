---
{
  "title": "Elixir Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track how long your Elixir project takes to compile with Mix, its warnings, and the files that hold your builds back."
}
---
# Elixir build insights {#elixir-build-insights}

Tuist's Hex package can send build analytics to Tuist. Build times, the dependency graph between your files, and how both evolve over time give you what you need to optimize your build graph and make the most of all the cores available in the environment where the compilation takes place.

> [!IMPORTANT] REQUIREMENTS
> - The <.localized_link href="/guides/install-hex-package">Hex package</.localized_link> installed and configured

## Report your builds {#report-your-builds}

Run `mix tuist.compile` instead of `mix compile`. It takes the same arguments and reports the build when it finishes:

```bash
mix tuist.compile --force
```

To report every build without anyone having to remember a different command, alias it in your `mix.exs`:

```elixir
def project do
  [
    app: :my_app,
    aliases: [compile: "tuist.compile"],
    tuist: [project: "account/project"]
  ]
end
```

The alias covers `mix compile` and every compile that another task triggers, such as `mix test` or `mix phx.server`. A compile that finds nothing to do is not reported, so the dashboard only lists builds that did work.

## Actor attribution {#actor-attribution}

Build and test reports automatically include the username from `USER`, `USERNAME`, or `LOGNAME` when available. Set `TUIST_ACTOR_ID` to override it per developer. A fixed `tuist: [project: "account/project", actor_id: "employee-123"]` in `mix.exs` applies to everyone using that configuration, so use it only for single-identity or CI setups. The environment takes precedence over project configuration. An empty override omits the reported identifier but does not remove credential-based verified identity.

On CI, automatic detection identifies the runner's OS account (for example, `runner` or `root`), not the developer who triggered the build. Use an explicit identifier when a different reporting identity is required.

Identifiers must be 1–128 bytes of non-space printable ASCII. Invalid overrides are omitted without falling back to the username. Verified individual credentials take precedence; other client-reported identifiers are displayed as **Unverified**, never authorize access, and never link automatically to users. Anyone who can view the project's reports can see these identifiers, including public viewers when the project is public, and they are included in data exports, so do not include secrets. Old servers ignore the optional header, and new servers accept old clients without it. New shared-token reports with no identifier show **Unknown**, rather than the publishing organization; historical reports retain their prior attribution. Build and test reporting require authentication by default. Self-hosted installations can explicitly enable credential-free reporting as described below.

## Credential-free reporting on a private network {#network-trusted-publishing}

After an operator configures `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true` on the instance and restarts it as described in the <.localized_link href="/guides/server/self-host/server#network-trusted-report-publishing">self-hosting guide</.localized_link>, configure your destination and opt in. The instance setting covers every supported project and has no dashboard toggle:

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project",
  network_trusted_publishing: true
]
```

Alternatively, set `TUIST_NETWORK_TRUSTED_PUBLISHING=true`. `mix tuist.compile` and `mix tuist.test` then publish structured reports without sign-in when credentials are genuinely absent. Present credentials, including supplied CI OIDC identity, are used or rejected, never ignored to downgrade to unsigned reporting. Blank tokens and corrupt credential files are errors and are not deleted automatically. Old servers reject unsigned reports.

Unsigned runs are telemetry, not trusted flakiness, quarantine, coverage, or selective-execution evidence. Shard planning, build archives, and coverage/artifact endpoints still require credentials. Set `TUIST_NETWORK_TRUSTED_PUBLISHING=false` to disable credential-free publishing even when the project configuration enables it. Set `TUIST_ACTOR_ID=""` independently to omit the username claim; verified credential identity is unaffected.

## What is tracked {#what-is-tracked}

For each build, the package collects:
- Its duration, whether it succeeded, and the Elixir, Erlang/OTP, and Mix environment it ran with
- Every warning and error, with its file and line
- How long each file took to compile, and the modules it defines
- The files each file depends on, and whether it needs them at compile time or only at runtime
- What the build did besides compiling files, such as type checking, writing to disk, and the other Mix compilers
- The processor, memory, network, and disk usage of the machine during the build
- The branch and commit, and on continuous integration, the provider and the run

## Find what slows a build down {#find-what-slows-a-build-down}

Open a build from **Builds → Build Runs** on the dashboard.

The **Overview** tab lists the files the build compiled. You can group them by module, search them, and sort them by:
- **Compilation duration**, to find the files that are slow by themselves.
- **Compile-time dependents**, the number of files that cannot compile until this one has. A slow file with many dependents holds the rest of the build back, and changing it recompiles all of them.
- **Compile-time dependencies**, the number of files this one waits for.

![Overview of a Mix build of a Phoenix application](/images/guides/features/elixir/build.png)

The **Timeline** tab shows the same build over time: which files compiled in parallel, where the build type checked and wrote to disk, and how the machine was doing at each moment. A stretch with a single bar is a stretch where the build could not use the cores it had.

![Timeline of a full Mix build of a Phoenix application](/images/guides/features/elixir/build-timeline.png)

The **Warnings** and **Errors** tabs list the diagnostics of the build.

## Custom metadata {#custom-metadata}

Attach tags and key-value data to Mix builds to tell apart runs from different teams, hardware, or workflows. Both appear on each build's detail page.

Set metadata with environment variables:

```sh
export TUIST_TAGS="nightly,release"
export TUIST_VALUES="ticket=TUIST-123,runner=linux-arm64"
```

You can also configure metadata in `mix.exs`:

```elixir
tuist: [
  project: "account/project",
  tags: ["nightly", "release"],
  values: %{"ticket" => "TUIST-123", "runner" => "linux-arm64"}
]
```

Tags from both places are combined. When the same key is configured in both places, the value in the environment variable takes precedence.

Tags must contain only letters, numbers, hyphens, and underscores. A build can have up to 50 tags, and each tag can contain up to 50 characters. A build can have up to 20 key-value entries, each key can contain up to 50 characters, and each value can contain up to 500 characters. These are the same server-side limits used for Xcode build metadata. The package skips invalid tags and oversized or empty metadata entries before it sends the report, so invalid configuration cannot prevent the rest of the build insights report from being stored. Use key-value metadata for values that do not meet the tag constraint.

Custom metadata is attached to builds, not to test runs.

Custom metadata is visible to project members in the dashboard. Do not use it for credentials, access tokens, or other sensitive data. Tuist retains Mix build data, including this metadata, for 90 days. See the <.localized_link href="/guides/server/data-retention">data retention policy</.localized_link> for details.

## Troubleshooting {#troubleshooting}

Reporting never changes the result of your build: if the report cannot be sent, the build finishes as it would have and nothing is printed. To see why a report was not sent, set `TUIST_DEBUG=1`:

```bash
TUIST_DEBUG=1 mix compile --force
```
