---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your Bitrise builds on Tuist Runners: connect your workspace, pair a self-hosted runner pool with a Tuist profile, and select the pool in your workflow."
}
---
# Bitrise {#bitrise}

> [!IMPORTANT]
> **Invite-only**
>
> Tuist Runners are currently invite-only. [Reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access for your account.

Tuist serves your Bitrise workspace's self-hosted runner pools. A build that selects one of those pools runs on a Tuist machine of the <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> you pair with the pool. Your workflows, triggers, and logs stay on Bitrise; only the machines change.

1. **Request access.** Runners are invite-only during the beta. [Reach out](mailto:contact@tuist.dev) with the account you want enabled.
2. **Connect your workspace.** In Bitrise, open **Workspace settings → Security → Workspace API tokens** and create a token with the **Viewer** workspace role and **Tester/QA** access to Bitrise CI for all projects. In your Tuist dashboard, go to **Settings → Integrations**, choose **Connect** on the Bitrise card, and paste the token. Tuist reads the workspace from the token, stores the token encrypted, and never shows it again.
3. **Create a runner pool.** In Bitrise, open **Workspace settings → Infrastructure**, choose **Add Runner pool**, and name it after the machine it stands for, for example `tuist-macos`. Copy the pool token: Bitrise shows it only once.
4. **Pair the pool with a Tuist profile.** On the Bitrise card in Tuist, under **Runner pools**, choose the pool, the Tuist profile its builds should run on, paste the pool token, and choose **Add pool**. Every enabled account starts with two profiles, `tuist-linux` and `tuist-macos`. Add one pool per profile you want to use.
5. **Select the pool in your workflow.** In Bitrise's Workflow Editor, open **Stacks & Machines** and choose **Self-Hosted Runner: tuist-macos**. In `bitrise.yml`, set the pool's stack, which Tuist shows under the pool's name:

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

6. **Run a build.** Within a few seconds, a Tuist machine connects to the pool, takes the build, and disconnects when it finishes. The build appears in the **Runners** section of your Tuist dashboard with its machine metrics and a link back to Bitrise, where its logs stay.

## Dedicated pools {#dedicated-pools}

Use the pools you pair with Tuist only for Tuist. If one of your own machines also connects to a paired pool, it competes with Tuist for that pool's builds.

## Runner limit {#runner-limit}

Each Tuist machine counts as one Bitrise runner while it runs a build, and stops counting when it disconnects. Your Bitrise plan's runner limit therefore caps how many of your builds run on Tuist at the same time, alongside your Tuist concurrency limit.

## Disconnecting {#disconnecting}

Removing a pool from the Bitrise card stops Tuist from taking that pool's builds. Builds already running are unaffected.

Choosing **Disconnect** on the Bitrise card removes the workspace and all its pools.
