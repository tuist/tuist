---
{
  "title": "執行器",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 執行器是專為 GitHub Actions、Buildkite、GitLab CI 和 Bitrise 設計的受管 macOS 與 Linux 執行器，其快取與運算資源共置，並與你的本機電腦共享。"
}
---
# 執行器 {#runners}

> [!IMPORTANT]
> **邀請制**
>
> Tuist Runners 目前為邀請制，我們正在擴充容量。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯絡我們，以請求開啟你帳戶的存取權限。當 Runners 全面開放時，我們將公布定價方案。


Tuist Runners 是受管的 macOS 與 Linux 執行器，適用於你的 GitHub Actions、Buildkite、GitLab CI 和 Bitrise 管線。與其將工作任務執行在 CI 供應商的主機上，不如將工作指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，讓它在 Tuist 的叢集上執行，並緊鄰團隊已使用的相同<.localized_link href="/guides/features/cache">快取</.localized_link>，無需安裝執行器代理程式，也無需維護基礎設施。若想在更換機器前了解影響 CI 費用的因素，請參閱[CI 成本](https://tuist.dev/solutions/ci-costs)。

採用方式通常只需對工作任務進行一行變更：

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

Linux 執行器預設透過 `/dev/kvm` 提供硬體加速虛擬化。使用一般的 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）即可執行 x86_64 Android 模擬器，包括 Gradle Managed Devices。無需特殊的執行器設定檔、KVM 設定動作、權限變更或 `sudo` 即可存取裝置。

執行器映像檔包含 Android SDK。在啟動裝置前，請先安裝模擬器及其執行階段程式庫。若專案已定義名為 `pixel6` 的 Gradle Managed Device，GitHub Actions 工作如下所示：

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

使用 Android Gradle Plugin 所需的 Java 版本，並將測試任務替換為專案的 managed-device 任務。設定 **x86_64** 系統映像檔。選擇具備足夠記憶體供 Gradle 與模擬器使用的執行器規格；並行裝置會共用該工作的 CPU 與記憶體配置。

以一般執行器使用者身分執行模擬器。此範例中的 `sudo` 僅用於安裝作業系統套件。

模擬器使用巢狀虛擬化，因此其時間可能與實體 Android 裝置不同。請將模擬器基準測試視為該 CI 環境的測量結果，而非實體裝置效能。

## 並行限制 {#concurrency-limits}

每個帳戶在 macOS 與 Linux 上皆有獨立的 vCPU 與記憶體並行限制。Tuist 在接受工作前，會檢查該工作的<.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link>與目前在該平台上執行的所有工作。只有當工作的 vCPU 與記憶體皆符合剩餘容量時，工作才會開始執行；否則會留在佇列中，直到容量可用為止。在某個平台上進行的工作絕不會消耗另一個平台的容量。

Runners 儀表板的**並行**區段顯示每小時的最高核准 vCPU 與記憶體用量。紅色橫條表示該小時內用量曾達到設定的限制。用量不會超過該線，因為會使任一資源超出限制的工作仍會留在佇列中。

每個圖表旁都會顯示你目前的限制。若你的工作流程經常達到限制並在佇列中等待，請[聯絡我們](mailto:contact@tuist.dev)，提供你的帳戶名稱、平台與預期平行工作量。我們會檢視所需容量並協助提高限制。

## 網路存取 {#network-access}

工作可以開啟連線至公開網際網路的出站連線。私有位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）已封鎖，且執行器不接受任何入站連線。

| 平台 | 出站連接埠 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 與 443 (HTTPS)，以及 DNS |
| macOS | 所有連接埠 |

SSH 涵蓋 `git@` 相依性、SSH 子模組、部署金鑰，以及 `ssh` 或 `scp` 部署。若 Linux 工作流程需要其他出站連接埠，請[聯絡我們](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連結 GitHub，將 runs-on 指向 Tuist 設定檔，並在叢集上執行你的第一個工作。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連結你的叢集，以 Tuist 設定檔命名佇列，並從步驟中指向該佇列。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連結 GitLab 一次，並以管線標籤選擇每個工作的機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="連結你的工作區，並在 Tuist 設定檔上執行自託管執行器集區的建置。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="透過單一請求從你自己的 git 平台或協調器執行工作，並使用 webhook 追蹤它們。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="設定檔"
    details="以你在工作中參考的具名機器設定檔，選擇平台、大小與 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="快取磁碟區"
    details="在工作之間保留 Xcode、模組與 Gradle 快取，以及任何其他目錄，每次執行都有專屬的可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Once 圖形動作 {#once-graph-actions}

當帳戶啟用遠端執行且伺服器宣告相容的工作者能力時，Once 可以在 Tuist 的 Linux 工作者上執行符合條件的圖形命令動作。這是動作層級的執行，與上述 CI 提供者工作分開。請參閱 <.localized_link href="/guides/features/runners/once">Once 遠端執行</.localized_link> 以了解設定、映像檔需求與相容性檢查。

## 為何選擇 Tuist Runners {#why-tuist-runners}

大多數 CI 執行器提供者透過提供更強大的機器與持久化快取來加速工作，通常是將共用磁碟區掛載回你的 CI 執行中。這確實有幫助，但磁碟區只是硬碟：它會保留先前 CI 執行所留下的任何內容。它不會複製以保持最新構件靠近建置執行處，也無法觸及程式碼在其他地方建置的位置。

建置不再只發生在單一位置。相同的程式碼會在開發者筆電、CI 環境，以及越來越多的編碼代理與其他自動化環境中編譯。Tuist Runners 的不同之處在於，它們共用所有這些環境已經讀寫的同個 <.localized_link href="/guides/features/cache">快取</.localized_link>，無論你使用哪種建置系統。隊友在筆電上預熱的構件、代理產生的構件，或先前建置留下的構件，在執行器上都會命中快取，反之亦然。不需要單獨預熱 CI 快取，且加速效果不限於 CI。

此外，快取與執行器位於同一私有網路上共置，因此快取讀寫保持在內部並靠近運算資源，無需跨越公開網際網路。

綜合而言：

- **跨所有環境共用。** 執行器與你的開發者機器、CI 及編碼代理讀寫相同的快取，因此在任何地方完成的工作都能為各處的快取預熱。
- **與運算資源共置。** 快取流量停留在執行器旁的內部網路上，而非經過公開入口。
- **單一系統，非外加元件。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link> 與 <.localized_link href="/guides/features/build-insights">建置洞察</.localized_link> 都針對同一專案與帳戶執行，因此執行器並非獨立的建置資料孤島。
