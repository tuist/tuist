---
{
  "title": "Runners",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 係專為 GitHub Actions 同 Buildkite 而設嘅受管理 macOS 同 Linux runner，配備與運算資源並置且可與你本地機器共享嘅快取。"
}
---
# Runners {#runners}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前仍為僅限邀請，因為我哋正擴展容量。[聯絡我哋](mailto:contact@tuist.dev)或喺[社區 Slack](https://slack.tuist.dev)通知我哋，為你嘅帳戶申請存取權。定價尚未公開；我哋會喺今年稍後時間，當 Runners 全面開放時公布。


Tuist Runners 係專為你嘅 GitHub Actions workflows 同 Buildkite pipelines 而設嘅受管 macOS 同 Linux runners。與其喺 CI 供應商嘅託管機器上執行 jobs，不如將 job 指向 Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>，佢就會喺 Tuist 嘅機隊上執行，同團隊已經使用緊嘅相同<.localized_link href="/guides/features/cache">cache</.localized_link>並排運行，無需安裝 runner agent，亦無基礎設施需要維護。

採用通常只需要對 job 進行一行更改：

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

## Linux 上嘅 Android 模擬器 {#android-emulators}

Linux runners 預設透過 `/dev/kvm` 提供硬件加速虛擬化。使用你普通嘅 Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>（例如 `tuist-linux`）來運行 x86_64 Android 模擬器，包括 Gradle Managed Devices。訪問設備無需特殊嘅 runner profile、KVM 設置動作、權限更改或 `sudo`。

Runner 映像包含 Android SDK。喺啟動設備之前，請安裝模擬器及其運行時庫。對於已經定義咗名為 `pixel6` 嘅 Gradle Managed Device 嘅項目，GitHub Actions job 看起來係這樣：

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

使用你嘅 Android Gradle Plugin 所需嘅 Java 版本，並將測試任務替換為你項目嘅 managed-device 任務。配置一個 **x86_64** 系統映像。選擇一個有足夠內存供 Gradle 同模擬器使用嘅 runner shape；併發設備共享 job 嘅 CPU 同內存分配。

以普通 runner 用戶身份運行模擬器。此示例中嘅 `sudo` 僅用於安裝操作系統軟件包。

模擬器使用嵌套虛擬化，因此其計時可能與實體 Android 設備不同。將模擬器基準測試視為該 CI 環境嘅測量結果，而非實體設備性能。

## 併發限制 {#concurrency-limits}

每個帳戶都有獨立嘅 macOS 同 Linux vCPU 同內存併發限制。喺 Tuist 接受 job 之前，它會檢查 job 嘅 <.localized_link href="/guides/features/runners/profiles#machine-shapes">machine shape</.localized_link> 與該平台上當前運行嘅所有 jobs。只有當 vCPU 同內存都符合剩餘容量時，job 才會開始；否則它會保持排隊狀態，直到容量可用。喺一個平台上嘅工作永遠不會消耗另一個平台嘅容量。

Runners 儀表板嘅 **Concurrency** 部分顯示每小時嘅峰值允許 vCPU 同內存使用量。紅色條表示使用量喺該小時內嘅某個時刻達到配置限制。使用量不能超過該線，因為會使任一資源超出其限制嘅 jobs 會保持排隊。

你當前嘅限制顯示喺每個圖表旁邊。如果你嘅 workflows 經常達到這些限制並花時間排隊，請[聯絡我哋](mailto:contact@tuist.dev)，提供你嘅帳戶名稱、平台同預期嘅並行工作量。我哋會審查所需容量並協助提高限制。

## 網絡訪問 {#network-access}

Jobs 可以打開到公共互聯網嘅出站連接。私有地址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）被阻止，且 runners 不接受任何入站連接。

| 平台 | 出站端口 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 同 443 (HTTPS)，以及 DNS |
| macOS | 所有端口 |

SSH 涵蓋 `git@` 依賴項、SSH submodules、deploy keys 以及 `ssh` 或 `scp` 部署。如果 Linux workflow 需要其他出站端口，請[聯絡我哋](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist profile，並喺機隊上運行你嘅第一個 job。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接你嘅 cluster，以 Tuist profile 命名 queue，並從 step 中定位它。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連接一次 GitLab，並使用 pipeline tags 為每個 job 選擇機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Profiles"
    details="通過你從 jobs 中引用嘅命名機器 profiles 選擇平台、大小同 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="Cache volumes"
    details="喺 jobs 之間保留 Xcode、module 同 Gradle caches 以及任何其他目錄，每次運行都有專用嘅可寫副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## 為什麼選擇 Tuist Runners {#why-tuist-runners}

大多數 CI runner 供應商通過提供更強大嘅機器同持久 cache（通常係掛載回你 CI 運行中嘅共享卷）來加快 jobs 速度。這有幫助，但卷只係磁盤：它攜帶以前 CI 運行留下嘅任何內容。它不會複製以保持最新 artifacts 靠近構建運行嘅地方，也永遠無法到達代碼構建嘅其他地方。

構建不再發生喺一個地方。相同嘅代碼喺開發者筆記本電腦、CI 以及越來越多嘅 coding agents 同其他自動化環境中編譯。Tuist Runners 之所以不同，係因為它們共享所有這些環境已經讀取同寫入嘅相同 <.localized_link href="/guides/features/cache">cache</.localized_link>，無論你使用什麼構建系統。隊友喺筆記本電腦上預熱嘅 artifacts、agent 產生嘅 artifacts 或早期構建留下嘅 artifacts 都會喺 runner 上命中，反之亦然。沒有單獨嘅 CI cache 需要預熱，而且加速不限於 CI。

除此之外，cache 與 runner 位於同一私有網絡上，因此 cache 讀寫保持內部並靠近計算，而不係跨越公共互聯網。

總結起來：

- **跨所有環境共享。** Runner 讀寫同你開發者機器、CI 同 coding agents 相同嘅 cache，所以任何地方完成嘅工作都會預熱各處嘅 cache。
- **與計算資源共置。** Cache 流量保留喺 runner 旁嘅內部網絡，而唔係經過公共入口。
- **單一系統，非外掛附加。** Caching、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">test sharding</.localized_link> 同 <.localized_link href="/guides/features/build-insights">build insights</.localized_link> 都針對同一個項目同帳戶運行，因此 runner 唔係獨立嘅構建數據孤島。
