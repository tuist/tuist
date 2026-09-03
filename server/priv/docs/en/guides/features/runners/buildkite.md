---
{
  "title": "Buildkite",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Run Buildkite jobs on Tuist Runners: connect your cluster, name a queue after a runner profile, and target it from your pipeline."
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **Invite-only**
>
> Tuist Runners are currently invite-only. [Reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access for your account.

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link>
> - A Buildkite [cluster](https://buildkite.com/docs/pipelines/clusters) with at least one self-hosted queue

Tuist watches the self-hosted queues in your Buildkite cluster and runs the jobs it finds there on the fleet. Your pipelines keep running on Buildkite; only the compute changes.

## Connect your cluster {#connect-your-cluster}

1. **Create a cluster agent token.** In Buildkite, open your cluster, go to **Agent Tokens**, and create one. It starts with `bkct_`.
2. **Add it to Tuist.** In your Tuist dashboard, go to **Runners → Buildkite**, enter your Buildkite organization slug and paste the token. The token is stored encrypted and is never shown again.

Tuist begins watching the cluster within a minute.

## Name a queue after a profile {#name-a-queue-after-a-profile}

A Buildkite job says where it wants to run with a queue, and a Tuist runner <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> describes what it runs on. Tuist connects the two by name: a job is picked up when its queue key matches one of your profiles.

Every enabled account starts with two profiles, `linux` and `macos`, so create self-hosted queues with those keys in your cluster:

```yaml
# .buildkite/pipeline.yml
steps:
  - label: "Test"
    command: tuist test
    agents:
      queue: macos
```

The **Runners → Buildkite** page lists the queue keys your profiles currently offer. Queues that match no profile are left alone, so your own agents keep serving them.

To use another Xcode version, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">create a profile</.localized_link> for it and add a queue with the same name.

> [!IMPORTANT]
> **Select Xcode with the runner profile**
>
> A macOS runner image contains a single Xcode version, which Tuist selects before the job starts based on the profile. Remove steps that use `xcode-select --switch` (or `xcode-select -s`): they commonly reference Xcode installations specific to hosted images and can fail on Tuist Runners. `xcodebuild`, `xcrun`, and `swift` use the profile's Xcode with no additional setup.

## What you get in the dashboard {#what-you-get-in-the-dashboard}

Buildkite jobs appear in the **Runners** section alongside everything else, with their logs, machine metrics, and duration. The agent ships each job's log to Tuist from inside the runner, so no additional Buildkite API token is needed.

## Pausing {#pausing}

Pausing dispatch on a Buildkite queue stops Tuist from taking new jobs from it. Jobs already running are unaffected.

Disconnecting the cluster in **Runners → Buildkite** stops Tuist watching it entirely.

## How jobs reach the fleet {#how-jobs-reach-the-fleet}

Tuist uses Buildkite's [Agent Stacks API](https://buildkite.com/docs/apis/agent-api/stacks), the interface Buildkite provides for running self-hosted queues on external compute:

1. Tuist lists the jobs scheduled on each matching queue and reserves them, so no other agent stack takes the same work.
2. When a runner is free, Tuist mints a single-job acquisition token for it. The token is bound to one job, so a runner can only ever run the job it was given.
3. The runner takes that job, runs it, and reports its log and outcome back to Tuist.

Because the acquisition token names one job, there is no window in which an idle agent sits registered against your cluster waiting to be handed work.

## Fork pull requests {#fork-pull-requests}

A job whose pull request comes from a fork does not get access to your account's warm cache and runs cold. If Tuist cannot positively determine that a job belongs to your own repository, it treats it as a fork.
