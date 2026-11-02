---
{
  "title": "Runners",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 係專為 GitHub Actions 同 Buildkite 而設嘅托管 macOS 同 Linux 執行環境，配備與運算資源並置且可與你本機共用嘅快取。"
}
---
# Runners {#runners}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請，因為我哋正擴展容量。[聯絡我哋](mailto:contact@tuist.dev)或喺[社區 Slack](https://slack.tuist.dev)留言，為你嘅帳戶申請存取權。定價尚未公開；當 Runners 全面開放時，我哋會喺今年稍後時間公佈。


Tuist Runners 係專為你嘅 GitHub Actions 工作流程同 Buildkite 流水線提供嘅受管 macOS 同 Linux 執行器。與其喺 CI 供應商嘅託管機器上運行作業，不如將作業指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，佢就會喺 Tuist 嘅機隊上運行，緊鄰你團隊已經使用緊嘅同一個<.localized_link href="/guides/features/cache">快取</.localized_link>，無需安裝任何執行器代理程式，亦無需維護基礎設施。

採用通常只需要對作業進行一行更改：

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

Linux 執行器預設透過`/dev/kvm`提供硬體加速虛擬化。使用你普通嘅 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如`tuist-linux`）來運行 x86_64 Android 模擬器，包括 Gradle Managed Devices。訪問設備無需特殊嘅執行器設定檔、KVM 設置動作、權限更改或`sudo`。

執行器映像包含 Android SDK。喺啟動設備之前，請安裝模擬器及其運行時庫。對於已定義名為`pixel6`嘅 Gradle Managed Device 嘅項目，GitHub Actions 作業如下所示：

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

使用你嘅 Android Gradle Plugin 所需嘅 Java 版本，並將測試任務替換為你項目嘅 managed-device 任務。配置一個**x86_64**系統映像。選擇一個有足夠內存供 Gradle 同模擬器使用嘅執行器規格；並發設備會共享作業嘅 CPU 同內存分配。

以普通執行器用戶身份運行模擬器。此示例中嘅`sudo`僅用於安裝操作系統軟件包。

模擬器使用嵌套虛擬化，因此其計時可能與實體 Android 設備不同。將模擬器基準測試視為對該 CI 環境嘅測量，而非實體設備性能。

## 併發限制 {#concurrency-limits}

每個帳戶都有獨立嘅 macOS 同 Linux vCPU 及內存併發限制。喺 Tuist 接受作業之前，它會檢查作業嘅<.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link>與該平台上當前運行嘅所有作業。只有當作業嘅 vCPU 同內存都符合剩餘容量時，作業才會開始；否則它會保持排隊狀態，直到容量可用。喺一個平台上嘅工作永遠不會消耗另一個平台嘅容量。

Runners 儀表板嘅**併發**部分顯示每小時峰值允許嘅 vCPU 同內存使用量。紅色條表示喺該小時內某個時間點使用量達到了配置限制。使用量不能超過該線，因為會使任一資源超出限制嘅作業仍會保持排隊。

你當前嘅限制顯示喺每個圖表旁邊。如果你嘅工作流程經常達到這些限制並花時間排隊，請[聯絡我哋](mailto:contact@tuist.dev)，提供你嘅帳戶名稱、平台同預期並行工作量。我哋會審查所需容量並協助提高限制。

## 網絡訪問 {#network-access}

作業可以打開到公共互聯網嘅出站連接。私有地址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）被阻止，且執行器不接受任何入站連接。

| 平台 | 出站端口 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 同 443 (HTTPS)，以及 DNS |
| macOS | 所有端口 |

SSH 涵蓋`git@`依賴項、SSH 子模塊、部署密鑰以及`ssh`或`scp`部署。如果 Linux 工作流程需要其他出站端口，請[聯絡我哋](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，並喺機隊上運行你嘅第一個作業。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接你嘅集群，以 Tuist 設定檔命名隊列，並從步驟中定位它。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連接一次 GitLab，並使用流水線標籤選擇每個作業嘅機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="設定檔"
    details="通過從作業中引用嘅命名機器設定檔，選擇平台、大小同 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="快取卷"
    details="喺作業之間保留 Xcode、模塊同 Gradle 快取以及任何其他目錄，每次運行都有專用嘅可寫副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## 為何選擇 Tuist Runners {#why-tuist-runners}

大多數 CI 執行器供應商通過提供更強大嘅機器同持久快取（通常係掛載回你 CI 運行中嘅共享卷）來加快作業速度。這有助益，但卷只係磁盤：它攜帶以前 CI 運行遺留嘅任何內容。它不會複製以保持最新構件靠近構建運行位置，也永遠無法到達代碼構建嘅其他地方。

構建不再發生喺單一位置。相同嘅代碼喺開發人員筆記本電腦、CI 環境，以及越來越多由編碼代理程式同其他自動化環境中編譯。Tuist Runners 唔同之處在於，無論你使用咩構建系統，它們都共享所有這些環境已經讀寫嘅同一個<.localized_link href="/guides/features/cache">快取</.localized_link>。同事喺筆記本電腦上預熱嘅構件、代理程式生成嘅構件或早期構建留下嘅構件都會喺執行器上命中，反之亦然。無需單獨預熱 CI 快取，且加速效果不限於 CI。

此外，快取與執行器位於同一私有網絡上，因此快取讀寫保持內部化並靠近計算資源，而無需跨越公共互聯網。

總結如下：

- **跨所有環境共享。** 執行器讀寫嘅快取同你嘅開發機器、CI 同編碼代理程式一樣，所以任何地方完成嘅工作都會為各處預熱快取。
- **與計算資源共置。** 快取流量停留喺執行器旁邊嘅內部網絡，而非通過公共入口。
- **單一系統，非附加組件。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link>同<.localized_link href="/guides/features/build-insights">構建洞察</.localized_link>都針對同一個項目同帳戶運行，因此執行器唔係獨立嘅構建數據孤島。
