---
{
  "title": "Getting started",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Run your first job on Tuist Runners from GitHub Actions or Buildkite: connect your CI provider, point a job at a Tuist profile, and watch it in the dashboard."
}
---
# Getting started {#getting-started}

> [!IMPORTANT]
> **Invite-only**
>
> Tuist Runners are currently invite-only. [Reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access for your account.


> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link>
> - For GitHub Actions, your project <.localized_link href="/guides/integrations/gitforge/github">connected to a GitHub organization</.localized_link>
> - For Buildkite, a [cluster](https://buildkite.com/docs/pipelines/clusters) with at least one self-hosted queue


Running a job on the fleet takes three changes: connect your CI provider, point a job at a Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>, and push.

## 1. Request access {#request-access}

Runners are invite-only during the beta. [Reach out](mailto:contact@tuist.dev) with the account you want enabled.

## 2. Connect your CI provider {#connect-your-ci-provider}

**GitHub Actions.** Make sure your project is <.localized_link href="/guides/integrations/gitforge/github">connected to your GitHub organization</.localized_link>. Tuist receives `workflow_job` events for that organization and dispatches matching jobs to the fleet. Without this connection, no jobs reach your runners.

**Buildkite.** In Buildkite, open your cluster, go to **Agent Tokens**, and create a token; it starts with `bkct_`. In your Tuist dashboard, go to **Settings → Integrations**, choose **Connect** on the Buildkite card, and enter your organization slug and the token. The token is stored encrypted and never shown again. To change the organization or rotate the token later, edit the fields on the card and choose **Save changes**. Tuist begins watching the cluster within a minute.

> [!WARNING]
> **Keep the pipeline, the queues and the token in one cluster**
>
> A Buildkite agent token is scoped to one cluster and only ever sees that cluster's queues, and a pipeline only dispatches to its own cluster's queues. Nothing in Buildkite warns you when they are split: queue names can match, the connection reports healthy, and jobs sit waiting forever. If you have more than one cluster, check the pipeline's **Settings → General → Cluster** after creating it.

## 3. Point a job at a Tuist profile {#point-a-job-at-a-tuist-profile}

Every enabled account starts with two ready-to-use <.localized_link href="/guides/features/runners/profiles">profiles</.localized_link>, `linux` and `macos`, referenced by their label with the `tuist-` prefix. On GitHub Actions the label goes in `runs-on`. On Buildkite, create a self-hosted queue in your cluster keyed with the label and target it from the step:

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos # or tuist-linux
    steps:
      - uses: actions/checkout@v4
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: "Test"
    command: tuist test
    agents:
      queue: tuist-macos # or tuist-linux
```
<!-- -->
:::

> [!IMPORTANT]
> **Use the profile's label, not its name**
>
> A profile named `macos` has the label `tuist-macos`, exactly as **Runners → Profiles** shows it. A job with `runs-on: macos`, or a Buildkite queue keyed `macos`, is never picked up, and nothing reports an error. Buildkite queues that match no profile are left alone, so your own agents keep serving them.

> [!IMPORTANT]
> **Select Xcode with the runner profile**
>
> A macOS runner image contains a single Xcode version, which Tuist selects before the job starts based on the profile. If you're migrating from hosted runners, remove steps that use `xcode-select --switch` (or `xcode-select -s`) or other tools and actions to switch Xcode versions. Those steps commonly reference Xcode installations specific to hosted images and can fail on Tuist Runners.
>
> To use another Xcode version, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">create or choose a profile</.localized_link> with that version and update the label, for example `tuist-xcode-26-4`. `xcodebuild`, `xcrun`, and `swift` will then use the profile's selected Xcode without any additional setup.

## 4. Push and watch {#push-and-watch}

The job is queued, claimed by a runner, and streamed back to the **Runners** section of your Tuist dashboard, where you can follow its logs, steps, and machine metrics. On Buildkite, the runner ships the log from inside the job with a credential scoped to that one job, so no Buildkite API token is needed.

## When a Buildkite job is not picked up {#when-a-buildkite-job-is-not-picked-up}

Work through these in order:

1. **Is the job on a queue keyed with a profile label?** Open the job in Buildkite and check the queue it is waiting on. It must equal a label from **Runners → Profiles**, `tuist-` prefix included. A step with no `agents` block goes to the cluster's default queue, which matches no profile.
2. **Are the pipeline, the queues and the token in the same cluster?** This is the most common cause and the hardest to see.
3. **Does the Buildkite card under Settings → Integrations show an error?** A revoked or wrong-cluster token is reported there.

Disconnecting the cluster on that card stops Tuist watching it entirely; jobs already running are unaffected.
