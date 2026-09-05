---
{
  "title": "Buildkite",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Run your first Buildkite job on Tuist Runners: connect your cluster, name a queue after a Tuist profile, and target it from a step."
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


Tuist watches the self-hosted queues in your Buildkite cluster and runs the jobs it finds there on the fleet. Your pipelines keep running on Buildkite; only the compute changes. Running a job on the fleet takes three changes: connect your cluster, name a queue after a Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>, and target it from a step.

1. **Request access.** Runners are invite-only during the beta. [Reach out](mailto:contact@tuist.dev) with the account you want enabled.
2. **Connect your cluster.** In Buildkite, open your cluster, go to **Agent Tokens**, and create a token; it starts with `bkct_`. In your Tuist dashboard, go to **Settings → Integrations**, choose **Connect** on the Buildkite card, and enter your organization slug and the token. The token is stored encrypted and never shown again. To change the organization or rotate the token later, edit the fields on the card and choose **Save changes**. Tuist begins watching the cluster within a minute.

3. **Name a queue after a Tuist profile.** Every enabled account starts with two ready-to-use <.localized_link href="/guides/features/runners/profiles">profiles</.localized_link>, `linux` and `macos`, and a job is picked up when its queue key matches a profile's label. Create self-hosted queues in your cluster keyed `tuist-linux` and `tuist-macos`, then target one from a step:

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

   > [!IMPORTANT]
   > **The queue key is the profile's label, not its name**
   >
   > A profile named `macos` has the label `tuist-macos`, exactly as **Runners → Profiles** shows it and the same string you would put in `runs-on:` on GitHub Actions. A queue keyed `macos` is never polled, and jobs sent to it wait forever with nothing reporting an error. Queues that match no profile are left alone, so your own agents keep serving them.

   > [!IMPORTANT]
   > **Select Xcode with the runner profile**
   >
   > A macOS runner image contains a single Xcode version, which Tuist selects before the job starts based on the profile. Remove steps that use `xcode-select --switch` (or `xcode-select -s`): they commonly reference Xcode installations specific to hosted images and can fail on Tuist Runners. To use another Xcode version, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">create a profile</.localized_link> for it and add a queue keyed with that profile's label. `xcodebuild`, `xcrun`, and `swift` then use the profile's Xcode with no additional setup.

4. **Push and watch.** The job is queued, claimed by a runner, and streamed back to the **Runners** section of your Tuist dashboard, where you can follow its logs, steps, and machine metrics. The runner ships the log from inside the job with a credential scoped to that one job, so no Buildkite API token is needed.

## When jobs are not picked up {#when-jobs-are-not-picked-up}

Work through these in order:

1. **Is the job on a queue keyed with a profile label?** Open the job in Buildkite and check the queue it is waiting on. It must equal a label from **Runners → Profiles**, `tuist-` prefix included. A step with no `agents` block goes to the cluster's default queue, which matches no profile.
2. **Are the pipeline, the queues and the token in the same cluster?** A token only sees its own cluster's queues, and a pipeline only dispatches to its own, so a split reports healthy and jobs wait. Queue names can match across clusters, which hides it. Check the pipeline's **Settings → General → Cluster**.
3. **Does the Buildkite card under Settings → Integrations show an error?** A revoked or wrong-cluster token is reported there.

A profile with no matching Buildkite queue is fine and is skipped quietly; you do not need a queue for every profile.

## Pausing and disconnecting {#pausing-and-disconnecting}

Pausing dispatch on a Buildkite queue stops Tuist from taking new jobs from it. Jobs already running are unaffected.

Disconnecting the cluster on the Buildkite card under **Settings → Integrations** stops Tuist watching it entirely.

## How jobs reach the fleet {#how-jobs-reach-the-fleet}

Tuist uses Buildkite's [Agent Stacks API](https://buildkite.com/docs/apis/agent-api/stacks), the interface Buildkite provides for running self-hosted queues on external compute:

1. Tuist lists the jobs scheduled on each matching queue and reserves them, so no other agent stack takes the same work.
2. When a runner is free, Tuist mints a single-job acquisition token for it. The token is bound to one job, so a runner can only ever run the job it was given.
3. The runner takes that job, runs it, and reports its log and outcome back to Tuist.

Because the acquisition token names one job, there is no window in which an idle agent sits registered against your cluster waiting to be handed work.

## Fork pull requests {#fork-pull-requests}

A job whose pull request comes from a fork does not get access to your account's warm cache and runs cold. If Tuist cannot positively determine that a job belongs to your own repository, it treats it as a fork.
