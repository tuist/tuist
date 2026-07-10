---
{
  "title": "Getting started",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Run your first GitHub Actions job on Tuist Runners: connect GitHub, point runs-on at a Tuist profile, and watch it in the dashboard."
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
> - Your project <.localized_link href="/guides/integrations/gitforge/github">connected to a GitHub organization</.localized_link>


Once your account is enabled, running a job on the fleet takes three changes: connect GitHub, point `runs-on` at a Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>, and push.

1. **Request access.** Runners are invite-only during the beta. [Reach out](mailto:contact@tuist.dev) with the account you want enabled.
2. **Connect GitHub.** Make sure your project is <.localized_link href="/guides/integrations/gitforge/github">connected to your GitHub organization</.localized_link>. Tuist receives `workflow_job` events for that organization and dispatches matching jobs to the fleet — without this connection, no jobs reach your runners.
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

## Next steps {#next-steps}

- Create additional <.localized_link href="/guides/features/runners/profiles">profiles</.localized_link> for other sizes or Xcode versions.
- Review the available platforms and machine shapes in the <.localized_link href="/guides/features/runners#platforms-and-machine-shapes">Runners overview</.localized_link>.
