---
{
  "title": "執行器",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 執行器是專為 GitHub Actions 與 Buildkite 設計的 macOS 和 Linux 受管執行環境，其快取與運算資源共置，並可與本機共用。"
}
---
# 執行器 {#runners}

> [!IMPORTANT]
> **邀請制**
>
> Tuist Runners 目前採邀請制，我們正在擴充容量。[聯絡我們](mailto:contact@tuist.dev)或在 [社群 Slack](https://slack.tuist.dev) 上留言，為你的帳戶申請存取權限。定價尚未公開；我們將於今年稍後、Runners 全面開放時公布。


Tuist Runners 是專為你的 GitHub Actions 工作流程與 Buildkite 流水線所管理的 macOS 與 Linux 執行器。與其讓工作在你的 CI 供應商託管機器上執行，不如將工作指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，它就會在 Tuist 的機群上執行，並緊鄰團隊已在使用的相同 <.localized_link href="/guides/features/cache">快取</.localized_link>，無需安裝執行器代理程式，也無須維護基礎設施。

採用通常只需對工作進行一行變更：

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

## Linux 上的 Android 模擬器 {#android-emulators}

Linux 執行器預設透過 `/dev/kvm` 提供硬體加速虛擬化。使用你慣用的 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）來執行 x86_64 Android 模擬器，包括 Gradle Managed Devices。存取裝置無需特殊的執行器設定檔、KVM 設定動作、權限變更或 `sudo`。

執行器映像檔包含 Android SDK。在啟動裝置前，請先安裝模擬器及其執行階段函式庫。若專案已定義名為 `pixel6` 的 Gradle Managed Device，GitHub Actions 工作會如下所示：

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

使用 Android Gradle Plugin 所需的 Java 版本，並將測試任務替換為專案的 managed-device 任務。設定 **x86_64** 系統映像檔。選擇具備足夠記憶體以同時支援 Gradle 與模擬器的執行器規格；並行裝置會共用該工作的 CPU 與記憶體配置。

以一般執行器使用者身分執行模擬器。此範例中的 `sudo` 僅用於安裝作業系統套件。

模擬器使用巢狀虛擬化，因此其計時可能與實體 Android 裝置不同。請將模擬器基準測試視為對該 CI 環境的測量，而非實體裝置效能。

## 並行限制 {#concurrency-limits}

每個帳戶在 macOS 與 Linux 上都有獨立的 vCPU 與記憶體並行限制。在 Tuist 接受工作之前，會檢查該工作的 <.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link> 與該平台上所有目前執行中的工作。只有當工作的 vCPU 與記憶體都能容納於剩餘容量內時，工作才會開始；否則會停留在佇列中，直到容量可用。在某個平台上的工作永遠不會消耗另一平台的容量。

Runners 儀表板的 **並行** 區段顯示每小時的最高核准 vCPU 與記憶體用量。紅色長條表示在該小時內的某個時間點，用量達到了設定的限制。用量不會超過該線，因為會使任一資源超出限制的工作會繼續留在佇列中。

你的目前限制會顯示在每個圖表旁。若你的工作流程經常達到這些限制並在佇列中等待，請[聯絡我們](mailto:contact@tuist.dev)，提供你的帳戶代號、平台與預計的平行工作量。我們將檢視所需容量並協助提高限制。

## 網路存取 {#network-access}

工作可以開啟通往公共網際網路的出站連線。私有位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）已被封鎖，且執行器不接受任何入站連線。

| 平台 | 出站通訊埠 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 與 443 (HTTPS)，以及 DNS |
| macOS | 所有通訊埠 |

SSH 涵蓋 `git@` 相依性、SSH 子模組、部署金鑰，以及 `ssh` 或 `scp` 部署。若 Linux 工作流程需要其他出站通訊埠，請[聯絡我們](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在機群上執行你的第一個工作。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接你的叢集，以 Tuist 設定檔命名佇列，並從步驟中指向該佇列。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="一次性連接 GitLab，並使用流水線標籤為每個工作選擇機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="設定檔"
    details="透過你在工作中參考的具名機器設定檔，選擇平台、大小與 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="快取磁碟區"
    details="在工作之間保留 Xcode、模組與 Gradle 快取，以及任何其他目錄，並為每次執行提供私有的可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## 為何選擇 Tuist Runners {#why-tuist-runners}

多數 CI 執行器供應商透過提供更強大的機器與持久化快取（通常是掛載回 CI 執行中的共用磁碟區）來加速工作。這確實有幫助，但磁碟區只是磁碟：它會保留先前 CI 執行所留下的任何內容。它不會複製以確保只有最新的構件靠近建置執行位置，也無法觸及程式碼在其他地方建置的位置。

建置不再只發生在單一位置。相同的程式碼會在開發者筆電、CI 環境，以及日益增多的編碼代理程式與其他自動化環境中編譯。Tuist Runners 的不同之處在於，它們共用所有這些環境已經讀寫的同一片 <.localized_link href="/guides/features/cache">快取</.localized_link>，無論你使用哪種建置系統。隊友在筆電上預熱的構件、代理程式產生的構件，或先前建置留下的構件，在執行器上都會命中快取，反之亦然。無需單獨預熱 CI 快取，且加速效果不限於 CI。

此外，快取與執行器位於同一私有網路上共置，因此快取讀寫保持在內部並靠近運算資源，而不需跨越公共網際網路。

綜合來說：

- **在所有環境中共用。** 執行器與你的開發者機器、CI 及編碼代理程式讀寫同一片快取，因此在任何地方完成的工作都能為各處預熱快取。
- **與運算資源共置。** 快取流量停留在執行器旁的內部網路上，而非透過公共入口。
- **單一系統，非外加元件。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link>與<.localized_link href="/guides/features/build-insights">建置洞察</.localized_link>皆針對同一專案與帳號執行，因此執行器不會成為獨立的建置資料孤島。
