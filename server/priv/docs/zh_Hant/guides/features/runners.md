---
{
  "title": "Runners",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Tuist Runners are managed macOS and Linux runners for GitHub Actions and Buildkite, with a cache colocated next to the compute and shared with your local machines."
}
---
# Runners {#runners}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前為僅限邀請，因為我們正在擴展容量。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯絡我們，以請求您的帳戶存取權限。定價尚未公開；我們將於今年稍後當 Runners 全面開放時宣布。


Tuist Runners 是專為您的 GitHub Actions 工作流程和 Buildkite 管線所管理的 macOS 與 Linux Runner。與其將工作執行於 CI 供應商的託管機器上，您可以將工作指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，它便會在 Tuist 的機隊上執行，緊鄰您團隊已使用的相同<.localized_link href="/guides/features/cache">快取</.localized_link>，無需安裝 Runner 代理程式，也無需維護基礎設施。

採用它們通常只需對工作進行一行變更：

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

Linux Runner 預設透過 `/dev/kvm` 提供硬體加速虛擬化。使用您慣用的 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）來執行 x86_64 Android 模擬器，包括 Gradle Managed Devices。無需特殊的 Runner 設定檔、KVM 設定動作、權限變更或 `sudo` 即可存取裝置。

Runner 映像包含 Android SDK。在啟動裝置之前，請先安裝模擬器及其執行階段程式庫。對於已定義名為 `pixel6` 之 Gradle Managed Device 的專案，GitHub Actions 工作如下所示：

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

使用您的 Android Gradle Plugin 所需的 Java 版本，並將測試任務替換為您專案的 managed-device 任務。設定 **x86_64** 系統映像。選擇具備足夠記憶體以同時支援 Gradle 與模擬器的 Runner 規格；並行裝置會共用該工作的 CPU 與記憶體配置。

以一般 Runner 使用者身分執行模擬器。此範例中的 `sudo` 僅用於安裝作業系統套件。

模擬器使用巢狀虛擬化，因此其計時可能與實體 Android 裝置不同。請將模擬器基準測試視為對該 CI 環境的測量，而非實體裝置效能。

## 並行限制 {#concurrency-limits}

每個帳戶針對 macOS 與 Linux 擁有獨立的 vCPU 與記憶體並行限制。在 Tuist 接受工作之前，它會檢查該工作的<.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link>與目前在該平台上執行的所有工作。只有當其 vCPU 與記憶體均符合剩餘容量時，工作才會開始；否則它將保持佇列狀態，直到容量可用為止。在某個平台上的工作絕不會消耗另一個平台的容量。

Runners 儀表板的**並行**區段顯示每小時的最高核准 vCPU 與記憶體使用量。紅色橫條表示使用量在該小時內的某個時間點達到了設定的限制。使用量無法超過該線，因為會使任一資源超出其限制的工作將保持佇列狀態。

您的目前限制顯示在每個圖表旁邊。如果您的工作流程經常達到這些限制並在佇列中花費時間，請[聯絡我們](mailto:contact@tuist.dev)，並提供您的帳戶代號、平台以及預期的平行工作負載。我們將檢視所需容量並協助提高限制。

## 網路存取 {#network-access}

工作可以開啟通往公共網際網路的出站連線。私有位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）已被封鎖，且 Runner 不接受任何入站連線。

| 平台 | 出站通訊埠 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 和 443 (HTTPS)，以及 DNS |
| macOS | 所有通訊埠 |

SSH 涵蓋 `git@` 依賴項、SSH 子模組、部署金鑰，以及 `ssh` 或 `scp` 部署。如果 Linux 工作流程需要其他出站通訊埠，請[聯絡我們](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在機隊上執行您的第一個工作。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接您的叢集，以 Tuist 設定檔命名佇列，並從步驟中將其設為目標。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連接 GitLab 一次，並使用管線標籤選擇每個工作的機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="設定檔"
    details="選擇平台、大小和 Xcode 版本，使用您可從工作中參考的具名機器設定檔。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="快取磁碟區"
    details="在工作之間保留 Xcode、模組和 Gradle 快取以及任何其他目錄，每次執行都有私有的可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## 為何選擇 Tuist Runners {#why-tuist-runners}

大多數 CI Runner 供應商透過提供更強大的機器和持久性快取（通常是掛載回您 CI 執行中的共用磁碟區）來加快工作速度。這有所幫助，但磁碟區只是磁碟：它會保留先前 CI 執行所留下的任何內容。它不會被複製以將最新的構件保持在靠近建置執行的位置，也永遠無法到達您程式碼建置的其他地方。

建置不再發生在單一位置。相同的程式碼會在開發人員的筆記型電腦、CI 環境中編譯，並且越來越多地由編碼代理程式和其他自動化環境編譯。Tuist Runners 的不同之處在於，它們共用所有這些環境已經讀取和寫入的相同<.localized_link href="/guides/features/cache">快取</.localized_link>，無論您使用哪種建置系統。隊友在筆記型電腦上預熱的構件、代理程式產生的構件，或先前建置留下的構件，在 Runner 上都會命中，反之亦然。沒有單獨的 CI 快取需要預熱，且加速不僅限於 CI。

此外，快取與 Runner 位於同一私有網路上共置，因此快取讀取和寫入保持在內部並靠近運算資源，而不是跨越公共網際網路。

總結如下：

- **在所有環境中共用。** Runner 會讀取和寫入與您的開發人員機器、CI 和編碼代理程式相同的快取，因此在任何地方完成的工作都會預熱各處的快取。
- **與運算資源共置。** 快取流量保留在 Runner 旁的內部網路上，而非透過公共入口。
- **單一系統，非附加元件。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link> 和 <.localized_link href="/guides/features/build-insights">建置洞察</.localized_link> 都針對同一專案和帳戶執行，因此 Runner 不是獨立的建置資料孤島。
