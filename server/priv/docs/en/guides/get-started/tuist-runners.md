---
{
  "title": "Run",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Run continuous integration and continuous delivery automations on managed Tuist macOS or Linux runners."
}
---
# Run {#tuist-runners}

Tuist runners execute GitHub Actions jobs on managed macOS and Linux <.localized_link href="/guides/integrations/continuous-integration">continuous integration</.localized_link> infrastructure. You can adopt them independently of project generation, then connect caching and insights when you want build work and data shared across developer machines and runners.

Tuist builds runners, caching, and insights as parts of the same infrastructure instead of treating them as separate services. Managed runners are colocated with the Tuist cache infrastructure they use, which shortens the path that build artifacts travel and reduces the latency of cache downloads and uploads.

> [!IMPORTANT]
> **Invite-only**
>
> Tuist runners are currently invite-only. [Contact Tuist](mailto:contact@tuist.dev) or ask in the [community Slack](https://slack.tuist.dev) to request access for your account.

## Keep compute close to build work {#keep-compute-close-to-build-work}

Build automations can move a large volume of compiled artifacts. When compute and cache storage are far apart, part of the time saved by a cache hit can be lost while those artifacts travel across the network. Colocating the runners and cache reduces that overhead, which makes cached work available to the build sooner.

The same Tuist project connects runner jobs and developer machines to shared build work. A successful build on the main branch can populate the cache, then later runner jobs and developer builds can reuse those results instead of compiling them again. This is especially valuable for larger Xcode and Gradle projects, where avoiding repeated compilation has a greater effect on feedback time.

Co-location improves artifact transfer performance, while the cache strategy determines how much work can be reused. Follow the <.localized_link href="/guides/get-started/optimization">Optimize path</.localized_link> to choose between module caching, Xcode compilation caching, and Gradle caching. Use the <.localized_link href="/guides/get-started/observability">Observe path</.localized_link> to compare cache activity and build duration before and after moving the automation.

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

After the first job succeeds, evaluate <.localized_link href="/guides/features/runners/profiles#machine-shapes">machine shapes</.localized_link> and account concurrency limits with representative workloads. Connect the relevant <.localized_link href="/guides/features/cache">cache</.localized_link> so builds on the main branch can populate reusable work for later jobs and developer machines. Then use <.localized_link href="/guides/features/build-insights">build insights</.localized_link> to confirm that cache activity and colocated infrastructure are reducing the duration of the automation before increasing machine capacity.
