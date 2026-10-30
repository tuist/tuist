---
{
  "title": "Runners",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 是为 GitHub Actions 和 Buildkite 提供的托管 macOS 和 Linux 运行器，缓存与计算资源并置，并与你的本地机器共享。"
}
---
# Runners {#runners}

> [!IMPORTANT]
> **仅限邀请**
>
> 在我们扩展容量期间，Tuist Runners 目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言，为你的账户申请访问权限。价格尚未公开；我们将在今年晚些时候 Runners 全面可用时公布。


Tuist Runners 是为你的 GitHub Actions 工作流和 Buildkite 流水线提供的托管 macOS 和 Linux 运行器。无需在 CI 提供商的托管机器上运行作业，你只需将作业指向 Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>，它就会在 Tuist 的运行器集群上执行，并与团队已使用的同一<.localized_link href="/guides/features/cache">cache</.localized_link>相邻，无需安装运行器代理，也无需维护基础设施。

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

默认情况下，Linux 运行器通过 `/dev/kvm` 提供硬件加速虚拟化。使用你常规的 Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>（例如 `tuist-linux`）来运行 x86_64 Android 模拟器，包括 Gradle Managed Devices。访问设备无需特殊的运行器配置文件、KVM 设置操作、权限更改或 `sudo`。

运行器镜像包含 Android SDK。在启动设备之前，请安装模拟器及其运行时库。对于已定义名为 `pixel6` 的 Gradle Managed Device 的项目，GitHub Actions 作业如下所示：

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

使用 Android Gradle Plugin 所需的 Java 版本，并将测试任务替换为项目的 managed-device 任务。配置一个 **x86_64** 系统镜像。选择具有足够内存的运行器规格，以同时满足 Gradle 和模拟器的需求；并发设备共享作业的 CPU 和内存分配。

以普通运行器用户身份运行模拟器。此示例中的 `sudo` 仅用于安装操作系统软件包。

模拟器使用嵌套虚拟化，因此其计时可能与物理 Android 设备不同。请将模拟器基准测试视为对该 CI 环境的测量，而非物理设备的性能。

## 并发限制 {#concurrency-limits}

每个账户对 macOS 和 Linux 都有独立的 vCPU 和内存并发限制。在 Tuist 接受作业之前，它会检查作业的 <.localized_link href="/guides/features/runners/profiles#machine-shapes">machine shape</.localized_link> 与该平台上当前运行的所有作业。只有当作业的 vCPU 和内存都符合剩余容量时，作业才会开始；否则它将保持排队状态，直到有可用容量。在一个平台上的工作永远不会消耗另一个平台的容量。

Runners 仪表板的 **Concurrency** 部分显示每小时峰值允许的 vCPU 和内存使用情况。红色条形表示在该小时内的某个时刻使用量达到了配置的限制。使用量不会超过该线，因为会使任一资源超出限制的作业将保持排队状态。

你的当前限制显示在每个图表旁边。如果你的工作流经常达到这些限制并花费时间排队，请[联系我们](mailto:contact@tuist.dev)，提供你的账户句柄、平台和预期的并行工作负载。我们将审查所需容量并帮助提高限制。

## 网络访问 {#network-access}

作业可以打开到公共互联网的出站连接。私有地址范围（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）被阻止，且运行器不接受任何入站连接。

| 平台 | 出站端口 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 和 443 (HTTPS)，以及 DNS |
| macOS | 所有端口 |

SSH 涵盖 `git@` 依赖项、SSH 子模块、部署密钥以及 `ssh` 或 `scp` 部署。如果 Linux 工作流需要其他出站端口，请[联系我们](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="连接 GitHub，将 runs-on 指向 Tuist 配置文件，并在集群上运行你的第一个作业。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="连接你的集群，以 Tuist 配置文件命名队列，并从步骤中定位它。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="一次性连接 GitLab，并使用流水线标签为每个作业选择机器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="配置文件"
    details="通过从作业中引用的命名机器配置文件，选择平台、大小和 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="缓存卷"
    details="在作业之间保留 Xcode、模块和 Gradle 缓存以及任何其他目录，每次运行都有专用的可写副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## 为什么选择 Tuist Runners {#why-tuist-runners}

大多数 CI 运行器提供商通过提供更强大的机器和持久缓存来加快作业速度，通常是挂载回 CI 运行中的共享卷。这有帮助，但卷只是磁盘：它携带之前 CI 运行留下的任何内容。它不会复制以保持最新的构件靠近构建运行的位置，也永远不会到达代码构建的其他地方。

构建不再发生在单一位置。相同的代码在开发者的笔记本电脑、CI 以及越来越多的编码代理和其他自动化环境中编译。Tuist Runners 的不同之处在于，它们共享所有那些环境已经读写相同的 <.localized_link href="/guides/features/cache">cache</.localized_link>，无论你使用什么构建系统。队友在笔记本电脑上预热的构件、代理生成的构件或早期构建留下的构件在运行器上都是命中，反之亦然。没有单独的 CI 缓存需要预热，加速也不仅限于 CI。

此外，缓存与运行器位于同一私有网络上，因此缓存读写保持在内部并靠近计算资源，而不是跨越公共互联网。

综上所述：

- **所有环境共享。** 运行器与你的开发者机器、CI 和编码代理读写相同的缓存，因此在任何地方完成的工作都会预热各处的缓存。
- **与计算资源共置。** 缓存流量保留在运行器旁边的内部网络上，而不是通过公共入口。
- **统一系统，非附加组件。** 缓存、<.localized_link href="/guides/features/selective-testing">选择性测试</.localized_link>、<.localized_link href="/guides/features/test-sharding">测试分片</.localized_link>和<.localized_link href="/guides/features/build-insights">构建洞察</.localized_link>都针对同一项目和账户运行，因此运行器不是孤立的构建数据孤岛。
