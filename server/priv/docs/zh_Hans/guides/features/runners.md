---
{
  "title": "Runners",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Tuist Runners are managed macOS and Linux runners for GitHub Actions and Buildkite, with a cache colocated next to the compute and shared with your local machines."
}
---
# Runners {#runners}

> [!IMPORTANT]
> **仅限邀请**
>
> 在我们扩展容量期间，Tuist Runners 目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中与我们取得联系，以请求为您的账户开通访问权限。定价尚未公开；我们将在今年晚些时候 Runners 全面可用时公布。


Tuist Runners 是用于您的 GitHub Actions 工作流和 Buildkite 流水线的托管 macOS 和 Linux Runner。无需在 CI 提供商的托管机器上运行作业，您只需将作业指向 Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>，它便会在 Tuist 的计算集群上运行，并与您的团队已经使用的相同<.localized_link href="/guides/features/cache">cache</.localized_link>相邻，无需安装 runner agent，也无需维护任何基础设施。

采用它们通常只需对作业进行一行更改：

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

## Linux 上的 Android 模拟器 {#android-emulators}

Linux Runner 默认通过 `/dev/kvm` 提供硬件加速虚拟化。使用您普通的 Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>（例如 `tuist-linux`）来运行 x86_64 Android 模拟器，包括 Gradle Managed Devices。访问设备无需特殊的 runner profile、KVM 设置操作、权限更改或 `sudo`。

Runner 镜像包含 Android SDK。在启动设备之前，请安装模拟器及其运行时库。对于已经定义了名为 `pixel6` 的 Gradle Managed Device 的项目，GitHub Actions 作业如下所示：

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

使用您的 Android Gradle Plugin 所需的 Java 版本，并将测试任务替换为您项目的 managed-device 任务。配置一个 **x86_64** 系统镜像。选择具有足够内存以同时运行 Gradle 和模拟器的 Runner 规格；并发设备共享作业的 CPU 和内存分配。

以普通 Runner 用户身份运行模拟器。此示例中的 `sudo` 仅用于安装操作系统软件包。

模拟器使用嵌套虚拟化，因此其计时可能与物理 Android 设备不同。请将模拟器基准测试视为对该 CI 环境的测量，而非物理设备的性能。

## 并发限制 {#concurrency-limits}

每个账户对于 macOS 和 Linux 都有独立的 vCPU 和内存并发限制。在 Tuist 接受作业之前，它会检查作业的 <.localized_link href="/guides/features/runners/profiles#machine-shapes">machine shape</.localized_link> 与该平台上当前运行的所有作业。只有当作业的 vCPU 和内存都符合剩余容量时，作业才会开始；否则，它将保持排队状态，直到有可用容量。在一个平台上的工作永远不会消耗另一个平台的容量。

Runners 仪表板的 **Concurrency** 部分显示每小时峰值允许的 vCPU 和内存使用情况。红色条形表示在该小时内的某个时刻使用情况达到了配置的限制。使用情况不会超过该线，因为会使任一资源超出其限制的作业将保持排队状态。

您当前的限制显示在每个图表旁边。如果您的工作流经常达到这些限制并花费时间排队，请[联系我们](mailto:contact@tuist.dev)，并提供您的账户句柄、平台和预期的并行工作负载。我们将审查所需容量并帮助提高限制。

## 网络访问 {#network-access}

作业可以打开到公共互联网的出站连接。私有地址范围（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）被阻止，且 Runner 不接受任何入站连接。

| 平台 | 出站端口 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 和 443 (HTTPS)，以及 DNS |
| macOS | 所有端口 |

SSH 涵盖 `git@` 依赖项、SSH 子模块、部署密钥以及 `ssh` 或 `scp` 部署。如果 Linux 工作流需要其他出站端口，请[联系我们](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="连接 GitHub，将 runs-on 指向 Tuist profile，并在计算集群上运行您的第一个作业。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="连接您的集群，以 Tuist profile 命名队列，并从步骤中定位它。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="一次性连接 GitLab，并使用流水线标签选择每个作业的机器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Profiles"
    details="选择平台、大小和 Xcode 版本，使用您在作业中引用的命名机器 profile。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="Cache volumes"
    details="在作业之间保留 Xcode、模块和 Gradle 缓存以及任何其他目录，每次运行都有私有的可写副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## 为什么选择 Tuist Runners {#why-tuist-runners}

大多数 CI Runner 提供商通过提供更强大的机器和持久缓存（通常是挂载回 CI 运行中的共享卷）来加快作业速度。这有帮助，但卷只是磁盘：它携带以前 CI 运行留下的任何内容。它不会复制以保持最新的工件靠近构建运行的位置，也永远不会到达代码构建的其他地方。

构建不再发生在单一位置。相同的代码在开发人员的笔记本电脑、CI 以及越来越多的编码代理和其他自动化环境中编译。Tuist Runners 的不同之处在于，它们共享所有那些环境已经读取和写入的相同 <.localized_link href="/guides/features/cache">cache</.localized_link>，无论您使用何种构建系统。队友在笔记本电脑上预热的工件、代理生成的工件或早期构建留下的工件在 Runner 上命中，反之亦然。没有单独的 CI 缓存需要预热，加速也不仅限于 CI。

此外，缓存与 Runner 位于同一私有网络上，因此缓存读写保持内部化并靠近计算资源，而不是跨越公共互联网。

综上所述：

- **在所有环境中共享。** Runner 读取和写入与您的开发机器、CI 和编码代理相同的缓存，因此在任何地方完成的工作都会预热各处的缓存。
- **与计算资源并置。** 缓存流量保留在 Runner 旁边的内部网络上，而不是通过公共入口。
- **一个系统，而非附加组件。** 缓存、<.localized_link href="/guides/features/selective-testing">选择性测试</.localized_link>、<.localized_link href="/guides/features/test-sharding">测试分片</.localized_link> 和 <.localized_link href="/guides/features/build-insights">构建洞察</.localized_link> 都针对同一个项目和账户运行，因此 Runner 不是独立的构建树数据孤岛。
