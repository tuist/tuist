---
{
  "title": "Xcode Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Xcode build analytics in the Tuist dashboard to monitor local and CI build performance."
}
---
# Xcode build insights {#xcode-build-insights}

Working on large projects should not require rebuilding the same code repeatedly. Tuist Build Insights lets you track build analytics so you can identify trends before local and CI build times become bottlenecks.

Build insights are driven by the `tuist inspect build` command, typically added to your scheme's post-action.

To start tracking local build times, you can leverage the `tuist inspect build` command by adding it to your scheme's post-action:

![Post-action for inspecting builds](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> Set the "Provide build settings from" field to the executable or your main build target to capture build configuration.


> [!NOTE]
> The post-scheme action is not executed when the build fails.

>
> You can execute it in that case by setting `runPostActionsOnFailure` to `YES` in the relevant `project.pbxproj` `BuildAction`:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

For [Mise](https://mise.jdx.dev/), activate `tuist` in the post-action environment:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise path resolution**
>
> Your environment's `PATH` is not inherited by the scheme post action, so use Mise's absolute path. This depends on how you installed Mise. Build settings should be inherited from a target so `mise` can run from `$SRCROOT`.

For [Homebrew](https://brew.sh/), add the Homebrew paths to the post-action environment:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Once logged in, local builds are tracked and available from the Tuist dashboard:

> [!TIP]
> To quickly access the dashboard, run `tuist project show --web` from the CLI.


![Dashboard with build insights](/images/guides/features/build-insights/builds-dashboard.png)

## Build Insights in CI {#continuous-integration}

To track build insights on CI, make sure CI is <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>.

For Xcodebuild-driven CI you need to:
- Use <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> when invoking `xcodebuild` actions.
- Add `-resultBundlePath` to your `xcodebuild` command.

Without `-resultBundlePath`, required activity logs and result bundles are not generated and `tuist inspect build` cannot analyze the build.

## Credential-free reporting on a private network {#network-trusted-publishing}

A self-hosted deployment can allow developers to publish completed reports without signing in. An operator must configure `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true` on the instance and restart it as described in the <.localized_link href="/guides/server/self-host/server#network-trusted-report-publishing">self-hosting guide</.localized_link>. This applies to every supported project; there is no dashboard setting. Configure the self-hosted URL and project, then opt in in the environment used by your scheme post-action or terminal:

```sh
export TUIST_URL="https://tuist.internal.example"
export TUIST_NETWORK_TRUSTED_PUBLISHING=true
tuist inspect build
# To publish local test results:
tuist inspect test
```

With genuinely absent credentials, activity logs and XCResult bundles are parsed locally and sent as structured reports. No raw archive, attachment, coverage/history upload, remote processor, shard reference, or selective-execution evidence is submitted. Reports remain visible but cannot update authenticated testcase state or drive quarantine/failure automations. Dashboards, cache, and other authenticated commands still require sign-in. Keep any cache integration disabled if credentials are not provisioned.

Present credentials remain authenticated. Invalid, corrupt, blank, or rejected-refresh credentials fail closed and remain on disk, so later commands do not silently become unsigned. Sign in again or explicitly sign out as a deliberate recovery action. Older servers reject unsigned reports. Set `TUIST_NETWORK_TRUSTED_PUBLISHING=false` to disable the client opt-in and `TUIST_ACTOR_ID=""` independently to omit the username claim; verified credential identity is unaffected.

## Machine metrics {#machine-metrics}

Build insights can include machine-level performance metrics (CPU, memory, network, and disk usage) captured during the build. To enable this, set up a lightweight background daemon that continuously samples system metrics:

```bash
tuist setup insights
```

This runs a local daemon that samples metrics in the background. The data is picked up automatically by `tuist inspect build` and uploaded with the build report.

> [!TIP]
> **Ci**
>
> Run `tuist setup insights` on your CI machines before building to capture machine metrics there as well.

To stop collecting machine metrics, run:

```bash
tuist teardown insights
```

This unloads the daemon's LaunchAgent, removes its plist, and deletes the sampled metrics and daemon logs from `~/.local/state`, so nothing is left running in the background.


## Actor attribution {#actor-attribution}

The CLI automatically sends `USER`, `USERNAME`, or `LOGNAME` as a reported actor identifier when available. Override it with `TUIST_ACTOR_ID`, for example `TUIST_ACTOR_ID=employee-123 tuist inspect build`. On CI, automatic detection identifies the runner's OS account rather than the person who triggered the build. Use an explicit identifier when needed. An empty `TUIST_ACTOR_ID` omits the reported identifier but does not remove credential-based verified identity. Identifiers must be 1–128 bytes of non-space printable ASCII; invalid overrides are omitted without falling back to the username.

Verified individual credentials take precedence; client-reported identifiers are otherwise shown as **Unverified** and never grant permissions or link automatically to users. Identifiers are visible to anyone who can view the project's reports, including public viewers when the project is public, and included in data exports, so do not include secrets. This applies to build, test, and command-event reports. Old servers ignore the optional header, and new servers accept old clients without it. New shared-token reports with no identifier show **Unknown**, rather than the publishing organization; historical reports retain their prior attribution. Build and test listings distinguish verified users from unverified reported identifiers. Authentication remains required unless credential-free reporting is explicitly enabled on both the self-hosted instance and client.

## Custom metadata {#custom-metadata}

You can attach metadata to builds with environment variables to improve filtering.

### Environment variables

| Variable | Format | Description |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Comma-separated | Multiple tags in one variable. |
| `TUIST_BUILD_VALUE_*` | Single value | Key-value pair where suffix is the key. |

### Examples

Set these values in CI or your shell before invoking your build:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
