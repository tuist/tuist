---
{
  "title": "Runners",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 係專為 GitHub Actions、Buildkite、GitLab CI 同 Bitrise 提供嘅受管 macOS 同 Linux 執行器，具備與運算資源共置並同你本地機器共享嘅快取。"
}
---
# Runners {#runners}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前處於僅限邀請階段，以便我們擴展容量。[聯絡我們](mailto:contact@tuist.dev)或在 [社區 Slack](https://slack.tuist.dev) 上聯絡我們，為你的帳戶申請存取權。當 Runners 全面開放時，我們會公佈定價。


Tuist Runners 是專為你的 GitHub Actions、Buildkite、GitLab CI 和 Bitrise 流程而設的受管 macOS 及 Linux runner。與其在你 CI 供應商的主機上執行工作，不如將工作指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，讓它在 Tuist 的機器群組上執行，並與你團隊已使用的同一個 <.localized_link href="/guides/features/cache">快取</.localized_link> 並存，無需安裝 runner agent，也無需維護基礎設施。若想在更換機器前了解影響你 CI 費用的因素，請參閱 [CI 成本](https://tuist.dev/solutions/ci-costs)。

採用它們通常只需對工作進行一行更改：

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

Linux runner 預設透過 `/dev/kvm` 提供硬體加速虛擬化。使用你一般的 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）來執行 x86_64 Android 模擬器，包括 Gradle Managed Devices。存取裝置無需特殊的 runner 設定檔、KVM 設定動作、權限變更或 `sudo`。

Runner 映像檔已包含 Android SDK。在啟動裝置之前，請先安裝模擬器及其執行時期函式庫。對於已定義名為 `pixel6` 的 Gradle Managed Device 的專案，GitHub Actions 工作如下所示：

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

使用你的 Android Gradle Plugin 所需的 Java 版本，並將測試任務替換為專案的 managed-device 任務。設定 **x86_64** 系統映像檔。選擇具有足夠記憶體供 Gradle 和模擬器使用的 runner 規格；同時執行的裝置會共用工作的 CPU 和記憶體配置。

以一般 runner 使用者身分執行模擬器。此範例中的 `sudo` 僅用於安裝作業系統套件。

模擬器使用巢狀虛擬化，因此其時間可能與實體 Android 裝置不同。請將模擬器基準測試視為該 CI 環境的測量結果，而非實體裝置效能。

## 並行限制 {#concurrency-limits}

每個帳戶對於 macOS 和 Linux 都有獨立的 vCPU 和記憶體並行限制。在 Tuist 接受工作之前，它會檢查該工作的 <.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link> 與目前在該平台上執行的所有工作。只有當工作的 vCPU 和記憶體都符合剩餘容量時，工作才會開始；否則它會保持佇列狀態，直到有可用容量為止。在一個平台上的工作絕不會消耗另一個平台的容量。

Air 帳戶具有固定的並行限制。對於 Pro 和 Enterprise 帳戶，Tuist 會根據經常性使用情況以及無法與活躍 runner 並存的最近佇列工作，自動增加緩衝空間。自動調整只會增加限制：現有的授權和合約最低容量都會保留。增長是漸進的，並受安全上限約束，因此突然的激增不會授予無限並行。較高的帳戶限制並不保證立即有可用的機器。

Runners 儀表板的 **並行** 部分顯示每小時峰值接受的 vCPU 和記憶體使用量，並以階梯線表示每小時開始時已知的限制。紅色長條達到該歷史閾值；它們本身並不能證明工作曾等待。一小時內的增加可能會使其峰值高於桶起始線。當前限制顯示在每個圖表旁邊。歷史追蹤開始之前的期間沒有限制線，而不是假設的歷史值。

如果工作流程繼續在安全上限處佇列，請 [聯絡我們](mailto:contact@tuist.dev) 並提供你的帳戶名稱、平台和預期平行工作量，以便我們檢視所需容量。

## 網路存取 {#network-access}

工作可以開啟連往公共網際網路的出站連線。私有位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）已被封鎖，且 runner 不接受任何入站連線。

| 平台 | 出站連接埠 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 和 443 (HTTPS)，加上 DNS |
| macOS | 所有連接埠 |

SSH 涵蓋 `git@` 依賴項、SSH 子模組、部署金鑰，以及 `ssh` 或 `scp` 部署。如果 Linux 工作流程需要其他出站連接埠，請 [聯絡我們](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在機器群組上執行你的第一個工作。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接你的叢集，以 Tuist 設定檔命名佇列，並從步驟中針對它。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連接一次 GitLab，並使用流水線標籤選擇每個工作的機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="連接你的工作區，並在 Tuist 設定檔上執行你自託管 runner 池的建構。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="透過單一請求從你自己的 git forge 或協調器執行工作，並使用 webhooks 追蹤它們。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="設定檔"
    details="使用你在工作中參考的具名機器設定檔，選擇平台、大小和 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="映像檔"
    details="查看 macOS 和 Linux runner 上預裝的內容：Xcode、模擬器、Metal 工具鏈、Docker、Android SDK 等。"
    link="/guides/features/runners/images"
/>
  <.home_card
    title="快取磁碟區"
    details="在不同工作之間保留 Xcode、模組和 Gradle 快取，以及任何其他目錄，並為每次執行提供私有的可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Once graph actions {#once-graph-actions}

當帳戶啟用遠端執行功能且伺服器宣傳相容的 worker 能力時，Once 可以在 Tuist 的 Linux worker 上執行符合條件的 graph command actions。這是 action 層級的執行，與上述 CI 供應商的工作分開。請參閱 <.localized_link href="/guides/features/runners/once">Once 遠端執行</.localized_link> 以了解設定、映像檔需求和相容性檢查。

## 為何選擇 Tuist Runners {#why-tuist-runners}

大多數 CI runner 供應商透過提供更強大的機器和持久化快取來加速工作，通常是一個掛載回你的 CI 執行中的共享磁碟區。這有幫助，但磁碟區只是磁碟：它會保留先前 CI 執行所留下的任何內容。它不會被複製以將最新的構件保持在靠近建構執行的地方，也無法觸及你程式碼建構的其他地方。

建構不再只發生在一個地方。相同的程式碼會在開發者的筆記型電腦、CI 環境，以及越來越多的編碼代理程式和其他自動化環境中編譯。Tuist Runners 的不同之處在於，它們共享所有這些環境已經讀取和寫入的同一個 <.localized_link href="/guides/features/cache">快取</.localized_link>，無論你使用哪種建構系統。隊友在筆記型電腦上預熱的構件、代理程式產生的構件，或先前建構留下的構件，都會在 runner 上命中，反之亦然。沒有單獨的 CI 快取需要預熱，而且加速效果不限於 CI。

此外，快取與 runner 位於同一個私有網路上，因此快取的讀取和寫入保持內部化並靠近運算資源，而不是跨越公共網際網路。

總結來說：

- **在所有環境中共享。** Runner 讀取和寫入的快取與你的開發者機器、CI 和編碼代理程式相同，因此在任何地方完成的工作都會預熱各處的快取。
- **與運算資源共置。** 快取流量停留在 runner 旁邊的內部網路上，而不是透過公共入口。
- **單一系統，非外掛附加。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link> 和 <.localized_link href="/guides/features/build-insights">建構洞察</.localized_link> 都針對同一個專案和帳戶執行，因此 runner 不是獨立的建構數據孤島。
