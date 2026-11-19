---
{
  "title": "執行器",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 執行器是專為 GitHub Actions、Buildkite、GitLab CI 與 Bitrise 設計的受管 macOS 與 Linux 執行器，其快取與運算資源共置，並與你的本機電腦共享。"
}
---
# Runners {#runners}

> [!IMPORTANT]
> **限邀請使用**
>
> Tuist Runners 目前處於限邀請階段，我們正在擴展容量。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們，以申請帳戶存取權限。當 Runners 全面開放時，我們將公布定價。


Tuist Runners 是專為 GitHub Actions、Buildkite、GitLab CI 和 Bitrise 流程提供的受管 macOS 與 Linux Runner。與其將工作執行於 CI 供應商的託管機器上，不如將工作指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，讓它在 Tuist 的機群上執行，並緊鄰團隊已使用的相同<.localized_link href="/guides/features/cache">快取</.localized_link>，無需安裝 Runner 代理程式，也無需維護基礎設施。若想在更換機器前了解影響 CI 帳單的因素，請參閱[CI 成本](https://tuist.dev/solutions/ci-costs)。

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

Linux Runner 預設透過 `/dev/kvm` 提供硬體加速虛擬化。使用一般的 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）即可執行 x86_64 Android 模擬器，包括 Gradle Managed Devices。存取裝置無需特殊的 Runner 設定檔、KVM 設定動作、權限變更或 `sudo`。

Runner 映像檔包含 Android SDK。在啟動裝置前，請先安裝模擬器及其執行階段函式庫。對於已定義名為 `pixel6` 之 Gradle Managed Device 的專案，GitHub Actions 工作如下所示：

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

使用 Android Gradle Plugin 所需的 Java 版本，並將測試任務替換為專案的 managed-device 任務。設定 **x86_64** 系統映像檔。選擇具備足夠記憶體以同時支援 Gradle 與模擬器的 Runner 規格；並行裝置會共用該工作的 CPU 與記憶體配置。

以一般 Runner 使用者身分執行模擬器。此範例中的 `sudo` 僅用於安裝作業系統套件。

模擬器使用巢狀虛擬化，因此其時間可能與實體 Android 裝置不同。請將模擬器基準測試視為對該 CI 環境的測量結果，而非實體裝置效能。

## 並行限制 {#concurrency-limits}

每個帳戶針對 macOS 與 Linux 擁有獨立的 vCPU 與記憶體並行限制。在 Tuist 接受工作之前，會檢查該工作的<.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link>是否符合該平台上所有目前正在執行的工作。只有當工作的 vCPU 與記憶體皆符合剩餘容量時，工作才會開始執行；否則它會留在佇列中，直到容量可用為止。在某個平台上的工作永遠不會消耗另一個平台的容量。

Air 帳戶具有固定的並行限制。對於 Pro 和 Enterprise 帳戶，Tuist 會根據經常性使用量以及近期無法與活躍 Runner 並行的佇列工作，自動增加緩衝空間。自動調整只會提高限制：現有的配額與合約最低容量都會保留。成長是漸進的，並受到安全上限的限制，因此突然的爆發不會授予無限並行能力。較高的帳戶限制並不保證能立即取得可用的機器。

Runners 儀表板中的**並行**區段顯示每小時的最高核准 vCPU 與記憶體使用量，並以階梯線表示每小時開始時已知的限制。紅色長條代表達到該歷史閾值；它們本身並不能證明工作曾等待。一小時內的增加可能使其峰值高於區間起始線。每個圖表旁邊會顯示目前的限制。在歷史追蹤開始之前的期間沒有顯示限制線，而非假設的歷史數值。

如果工作流程持續在安全上限處排隊，請[聯絡我們](mailto:contact@tuist.dev)，提供您的帳戶代號、平台以及預期的平行工作量，以便我們檢視所需容量。

## 網路存取 {#network-access}

工作可以開啟通往公共網際網路的出站連線。私有位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）已被封鎖，且 Runner 不接受任何入站連線。

| 平台 | 出站通訊埠 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 和 443 (HTTPS)，以及 DNS |
| macOS | 所有通訊埠 |

SSH 涵蓋 `git@` 相依性、SSH 子模組、部署金鑰，以及 `ssh` 或 `scp` 部署。如果 Linux 工作流程需要其他出站通訊埠，請[聯絡我們](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在機群上執行您的第一個工作。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接您的叢集，以 Tuist 設定檔命名佇列，並從步驟中指向它。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連接一次 GitLab，並使用流水線標籤選擇每個工作的機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="連接您的工作區，並在 Tuist 設定檔上執行自託管 Runner 集區的建置。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="透過單一請求從您自己的 Git 平台或協調器執行工作，並使用 Webhook 追蹤它們。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="設定檔"
    details="選擇平台、大小和 Xcode 版本，使用您可從工作中參考的具名機器設定檔。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="映像檔"
    details="查看 macOS 和 Linux Runner 上預先安裝的內容：Xcode、模擬器、Metal 工具鏈、Docker、Android SDK 等。"
    link="/guides/features/runners/images"
/>
  <.home_card
    title="快取磁碟區"
    details="在工作之間保留 Xcode、模組與 Gradle 快取，以及任何其他目錄，並為每次執行提供私有的可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo 圖形動作 {#struo-graph-actions}

<a id="once-graph-actions"></a>

當帳戶啟用遠端執行且伺服器宣告相容的 Worker 能力時，Struo 可以在 Tuist 的 Linux Worker 上執行符合資格的圖形指令動作。這是動作層級的執行，與上述 CI 供應商的工作分開。請參閱<.localized_link href="/guides/features/runners/struo">Struo 遠端執行</.localized_link>以了解設定、映像檔需求與相容性檢查。

## 為什麼選擇 Tuist Runners {#why-tuist-runners}

大多數 CI Runner 供應商透過提供更強大的機器與持久化快取來加速工作，通常是一個掛載回 CI 執行的共用磁碟區。這確實有幫助，但磁碟區只是磁碟：它會保留先前 CI 執行留下的任何內容。它不會為了讓最新的構件靠近建置執行位置而進行複寫，也無法觸及程式碼在其他地方建置的環境。

建置不再只發生在單一地點。相同的程式碼會在開發者的筆記型電腦、CI 環境，以及越來越多的編碼代理與其他自動化環境中編譯。Tuist Runners 的不同之處在於，它們與所有這些環境共用同一個<.localized_link href="/guides/features/cache">快取</.localized_link>，無論你使用哪種建置系統，這些環境都會從該快取讀取與寫入。隊友在筆記型電腦上預熱的構件、代理產生的構件，或先前的建置留下的構件，都能在 Runner 上命中快取，反之亦然。不需要單獨預熱 CI 快取，而且加速效果不限於 CI。

此外，快取與 Runner 位於相同的私有網路上，因此快取的讀寫保持在內部並靠近運算資源，而不需跨越公共網際網路。

綜合起來：

- **在所有環境中共用。** Runner 與你的開發者機器、CI 與編碼代理讀寫相同的快取，因此在任何地方完成的工作都能為各處的快取預熱。
- **與運算資源共置。** 快取流量停留在 Runner 旁的內部網路上，而非經過公共入口。
- **單一系統，非外掛附加。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link>與<.localized_link href="/guides/features/build-insights">建置洞察</.localized_link>都針對同一專案與帳戶執行，因此 Runner 不會成為獨立的建置資料孤島。
