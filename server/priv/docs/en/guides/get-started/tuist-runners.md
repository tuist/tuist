---
{
  "title": "Tuist runners",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Run a first GitHub Actions workflow on managed Tuist macOS or Linux runners."
}
---
# Tuist runners {#tuist-runners}

Tuist runners execute GitHub Actions jobs on managed macOS and Linux infrastructure. Adopt them independently of project generation, then connect caching and insights when you want build work and data shared across developer machines and runners.

> [!IMPORTANT]
> **Invite-only**
>
> Tuist runners are currently invite-only. [Contact Tuist](mailto:contact@tuist.dev) or ask in the [community Slack](https://slack.tuist.dev) to request access for your account.

## Adoption steps {#adoption-steps}

1. Choose the <.localized_link href="/guides/server/accounts-and-projects">Tuist account</.localized_link> that will own the runner profiles and the project that will connect to the GitHub organization.
2. Follow the <.localized_link href="/guides/features/runners/getting-started">runner getting-started guide</.localized_link> to connect the project to its GitHub organization.
3. Start with the default `macos` or `linux` profile. To choose a different machine size or Xcode version, create a named profile with the <.localized_link href="/guides/features/runners/profiles">runner profiles guide</.localized_link>.
4. Change a workflow job's `runs-on` value:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

5. Remove workflow steps that switch Xcode versions. A macOS runner profile selects the Xcode image before the job starts.
6. Push the workflow change and open the Runners section of the Tuist dashboard.

## Verify your setup {#verify-your-setup}

Confirm all of the following on the first workflow run:

- GitHub assigns the job to the `tuist-macos` or `tuist-linux` label instead of a GitHub-hosted runner.
- The job leaves the queue, completes its checkout and build steps, and reports its final status to GitHub Actions.
- The Tuist dashboard shows the run, step logs, and machine metrics.
- On macOS, `xcodebuild -version` reports the Xcode version selected by the profile.

After the first job succeeds, evaluate <.localized_link href="/guides/features/runners/profiles#machine-shapes">machine shapes</.localized_link> and account concurrency limits with representative workloads. Then connect the relevant <.localized_link href="/guides/features/cache">cache</.localized_link> and <.localized_link href="/guides/features/build-insights">build insights</.localized_link> guides so runner work is shared with the rest of the team.
