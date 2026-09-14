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

4. **Push and watch.** The job is queued, claimed by a runner, and streamed back to the **Runners** section of your Tuist dashboard, where you can follow its logs, steps, and machine metrics. The runner ships the log from inside the job with a credential scoped to that one job, so no Buildkite API token is needed.

## Pausing and disconnecting {#pausing-and-disconnecting}

Pausing dispatch on a Buildkite queue stops Tuist from taking new jobs from it. Jobs already running are unaffected.

Disconnecting the cluster on the Buildkite card under **Settings → Integrations** stops Tuist watching it entirely.
