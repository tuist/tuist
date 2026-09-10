---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Run GitLab CI jobs on Tuist Runners by connecting a GitLab runner to a Tuist profile."
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **Invite-only**
>
> Tuist Runners are currently invite-only. [Reach out](mailto:contact@tuist.dev) to request access for your account.

Your pipelines stay in GitLab. Tuist provides an isolated Linux or macOS machine for each job and reports its logs and outcome to GitLab and the Tuist dashboard. GitLab.com and self-managed instances reachable over public HTTPS are supported.

1. **Choose a profile.** Use `tuist-linux`, `tuist-macos`, or a custom <.localized_link href="/guides/features/runners/profiles">profile label</.localized_link>.
2. **Create a GitLab runner.** In your project's **Settings → CI/CD → Runners**, create a project runner. You can also use a group runner. Set its tag to your Tuist profile label and disable **Run untagged jobs**. Keep the authentication token GitLab shows, which starts with `glrt-`. You do not need to install or register a runner on your own machine.
3. **Connect it to Tuist.** In **Settings → Integrations**, choose **Connect** on the GitLab CI card. Enter your GitLab URL, Tuist profile label and runner authentication token. Create a separate runner and connection for each profile. Tokens are stored encrypted and are never displayed again.
4. **Target the runner in your pipeline:**

   ```yaml
   # .gitlab-ci.yml
   test:
     tags: [tuist-macos]
     script:
       - tuist test
     retry:
       max: 2
       when: runner_system_failure
   ```

5. **Push and watch.** Tuist starts polling within a minute. Jobs appear under **Runners**, with a link back to the GitLab job, logs and machine metrics. GitLab receives logs while the job runs; Tuist receives the masked log when it finishes.

## Execution environment {#execution-environment}

Jobs use GitLab's **shell executor** inside an isolated machine. Checkout, CI variables, `before_script`, `script`, `after_script`, artifacts and cancellation are handled by GitLab Runner. The pipeline's `image:` and `services:` settings do not configure this shell environment; use tools installed on the <.localized_link href="/guides/features/runners/profiles">runner image</.localized_link> or install them in your script.

The reusable runner authentication token stays on the Tuist server. Machines receive credentials for their assigned job only. Shared account cache volumes and cache-signing grants are currently withheld for GitLab jobs; GitLab CI variables can be overridden by a pipeline and cannot establish whether a job is trusted. GitLab's local cache therefore lasts for that machine's lifetime.

GitLab considers a job assigned as soon as Tuist acquires it. If no machine becomes available within ten minutes, Tuist fails the assignment with `runner_system_failure`. The retry policy above lets GitLab retry it. The same policy covers a lost runner machine.

## Rotating tokens and disconnecting {#rotating-tokens-and-disconnecting}

Update the connection's token and choose **Save changes** to rotate it. Leaving the token blank preserves the existing credential.

**Disconnect** stops acquisition and fails waiting assignments. Running jobs continue with their own credentials. If GitLab cannot be reached, Tuist retains the disabled connection while retrying the cancellation of waiting assignments. The connection is removed once those assignments have settled.
