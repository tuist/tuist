---
{
  "title": "Runners",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Tuist Runners are managed macOS and Linux runners for GitHub Actions, Buildkite, GitLab CI, and Bitrise, with a cache colocated next to the compute and shared with your local machines."
}
---
# Runners {#runners}

Tuist Runners are managed macOS and Linux runners for your GitHub Actions, Buildkite, GitLab CI, and Bitrise pipelines. Instead of running jobs on your CI provider's hosted machines, you point a job at a Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> and it runs on Tuist's fleet, next to the same <.localized_link href="/guides/features/cache">cache</.localized_link> your team already uses, with no runner agent to install and no infrastructure to maintain. To work out what drives your CI bill before changing machines, see [CI costs](https://tuist.dev/solutions/ci-costs).

Adopting them is usually a one-line change to a job:

::: code-group

```diff [GitHub Actions]
 jobs:
   build:
-    runs-on: macos-latest
+    runs-on: tuist-macos
     steps:
       - uses: actions/checkout@v4
       - run: tuist test
```

```diff [Buildkite]
 steps:
   - label: "Test"
     command: tuist test
     agents:
-      queue: macos
+      queue: tuist-macos
```
<!-- -->
:::

## Android emulators on Linux {#android-emulators}

Linux runners provide hardware-accelerated virtualization through `/dev/kvm` by default. Use your ordinary Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>, such as `tuist-linux`, to run x86_64 Android emulators, including Gradle Managed Devices. No special runner profile, KVM setup action, permission change, or `sudo` is needed to access the device.

The runner image includes the Android SDK. Install the emulator and its runtime libraries before starting a device. For a project that already defines a Gradle Managed Device named `pixel6`, a GitHub Actions job looks like this:

```yaml
jobs:
  android-test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - name: Install emulator dependencies
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y --no-install-recommends \
            libx11-6 libxcomposite1 libxcursor1 libxi6 libxtst6 libxrandr2 \
            libxrender1 libpulse0 libnss3 libxkbcommon-x11-0 libxcb-cursor0 \
            libasound2 libglu1-mesa
          "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" 'emulator'
      - name: Check hardware acceleration
        run: |
          test -r /dev/kvm && test -w /dev/kvm
          "$ANDROID_HOME/emulator/emulator" -accel-check
      - name: Run instrumented tests
        run: ./gradlew :app:pixel6DebugAndroidTest
```

Use the Java version required by your Android Gradle Plugin and replace the test task with your project's managed-device task. Configure an **x86_64** system image. Choose a runner shape with enough memory for both Gradle and the emulators; concurrent devices share the job's CPU and memory allocation.

Run the emulator as the normal runner user. `sudo` in this example is only for installing operating-system packages.

Emulators use nested virtualization, so their timings can differ from a physical Android device. Treat emulator benchmarks as measurements of that CI environment, rather than physical-device performance.

## Concurrency limits {#concurrency-limits}

Each account has independent vCPU and memory concurrency limits for macOS and Linux. Before Tuist admits a job, it checks the job's <.localized_link href="/guides/features/runners/profiles#machine-shapes">machine shape</.localized_link> against all jobs currently running on that platform. The job starts only when both its vCPU and memory fit within the remaining capacity; otherwise it stays queued until capacity becomes available. Work on one platform never consumes the other platform's capacity.

Air accounts have fixed concurrency limits. For Pro and Enterprise accounts, Tuist automatically adds headroom based on recurring usage and recent queued work that cannot fit alongside active runners. Automatic adjustments only increase limits: existing grants and contractual minimum capacity are preserved. Growth is gradual and bounded by safety ceilings, so a sudden burst does not grant unlimited concurrency. A higher account limit does not guarantee immediately available machines.

The **Concurrency** section of the Runners dashboard shows the peak admitted vCPU and memory usage for every hour, with a stepped line for the limit known at the start of each hour. Red bars reached that historical threshold; they do not by themselves prove a job waited. An increase during an hour can put its peak above the bucket-start line. Current limits are shown alongside each chart. Periods before history tracking began have no limit line rather than an assumed historical value.

If workflows continue to queue at the safety ceiling, [contact us](mailto:contact@tuist.dev) with your account handle, platform, and expected parallel workload so we can review the required capacity.

## Network access {#network-access}

Jobs can open outbound connections to the public internet. Private address ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) are blocked, and runners accept no inbound connections.

| Platform | Outbound ports |
| --- | --- |
| Linux | TCP 22 (SSH), 80 (HTTP), and 443 (HTTPS), plus DNS |
| macOS | All ports |

SSH covers `git@` dependencies, SSH submodules, deploy keys, and `ssh` or `scp` deploys. If a Linux workflow needs another outbound port, [contact us](mailto:contact@tuist.dev).

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="Connect GitHub, point runs-on at a Tuist profile, and run your first job on the fleet."
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="Connect your cluster, name a queue after a Tuist profile, and target it from a step."
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="Connect GitLab once and choose each job’s machine with pipeline tags."
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="Connect your workspace and run builds of your self-hosted runner pools on Tuist profiles."
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="Run jobs from your own git forge or orchestrator with one request and follow them with webhooks."
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="Profiles"
    details="Choose a platform, size, and Xcode version with named machine profiles you reference from your jobs."
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="Images"
    details="See what's preinstalled on macOS and Linux runners: Xcode, simulators, the Metal toolchain, Docker, the Android SDK and more."
    link="/guides/features/runners/images"
/>
  <.home_card
    title="Cache volumes"
    details="Keep the Xcode, module and Gradle caches and any other directory between jobs, with a private writable copy for each run."
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo graph actions {#struo-graph-actions}

<a id="once-graph-actions"></a>

Struo can execute eligible graph command actions on Tuist's Linux workers when the account has remote execution enabled and the server advertises compatible worker capabilities. This is action-level execution, separate from the CI-provider jobs above. See <.localized_link href="/guides/features/runners/struo">Struo remote execution</.localized_link> for setup, image requirements, and compatibility checks.

## Why Tuist Runners {#why-tuist-runners}

Most CI runner providers make jobs faster by giving you beefier machines and a persistent cache, typically a shared volume mounted back into your CI runs. That helps, but a volume is just a disk: it carries whatever previous CI runs happened to leave on it. It isn't replicated to keep just the freshest artifacts close to where builds run, and it never reaches the other places your code gets built.

Building doesn't happen in one place anymore. The same code is compiled on developer laptops, across CI, and increasingly by coding agents and other automated environments. Tuist Runners are different because they share the same <.localized_link href="/guides/features/cache">cache</.localized_link> all of those environments already read from and write to, whatever build system you use. Artifacts that a teammate warmed on their laptop, that an agent produced, or that an earlier build left behind are a hit on the runner, and vice versa. There's no separate CI cache to warm up, and the speedup isn't limited to CI.

On top of that, the cache is colocated with the runner on the same private network, so cache reads and writes stay internal and close to the compute instead of crossing the public internet.

Put together:

- **Shared across every environment.** The runner reads and writes the same cache as your developer machines, CI, and coding agents, so work done anywhere warms the cache everywhere.
- **Colocated with the compute.** Cache traffic stays on the internal network next to the runner, not over a public ingress.
- **One system, not bolted-on.** Caching, <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link>, <.localized_link href="/guides/features/test-sharding">test sharding</.localized_link>, and <.localized_link href="/guides/features/build-insights">build insights</.localized_link> all run against the same project and account, so the runner isn't a separate silo of build data.
