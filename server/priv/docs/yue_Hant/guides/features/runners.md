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
> Tuist Runners 目前正處於擴充容量階段，因此僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯絡我們，以申請存取你的帳戶。定價尚未公開；我們將於今年稍後時間公佈，屆時 Runners 將全面開放使用。


Tuist Runners 是專為你的 GitHub Actions 工作流程和 Buildkite 流水線而設的受管 macOS 及 Linux runner。與其在你 CI 供應商的主機上執行作業，不如將作業指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，讓它在 Tuist 的機群上執行，並與你團隊已使用的相同<.localized_link href="/guides/features/cache">快取</.localized_link>並存，無需安裝 runner agent，也無需維護基礎設施。

採用它們通常只需對作業進行一行變更：

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

Runner 映像包含 Android SDK。在啟動裝置之前，請先安裝模擬器及其執行階段程式庫。對於已定義名為 `pixel6` 的 Gradle Managed Device 的專案，GitHub Actions 作業如下所示：

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

使用你的 Android Gradle Plugin 所需的 Java 版本，並將測試任務替換為專案的 managed-device 任務。設定 **x86_64** 系統映像。選擇具有足夠記憶體供 Gradle 和模擬器使用的 runner 規格；同時執行的裝置會共用作業的 CPU 和記憶體配置。

以一般 runner 使用者身分執行模擬器。此範例中的 `sudo` 僅用於安裝作業系統套件。

模擬器使用巢狀虛擬化，因此其計時可能與實體 Android 裝置不同。請將模擬器基準測試視為該 CI 環境的測量結果，而非實體裝置效能。

## 並行限制 {#concurrency-limits}

每個帳戶都有獨立的 macOS 和 Linux vCPU 及記憶體並行限制。在 Tuist 接受作業之前，它會檢查作業的 <.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link> 與該平台上目前執行的所有作業。只有當作業的 vCPU 和記憶體都符合剩餘容量時，作業才會開始執行；否則它會保持佇列狀態，直到有可用容量為止。在一個平台上的工作永遠不會消耗另一個平台的容量。

Runners 儀表板的 **並行** 區段顯示每小時的最高核准 vCPU 和記憶體用量。紅色條形表示用量在某個時間點達到了設定的限制。用量無法超過該線條，因為會使任一資源超出其限制的作業會保持佇列狀態。

你的目前限制顯示在每個圖表旁邊。如果你的工作流程經常達到這些限制並花費時間在佇列中，請[聯絡我們](mailto:contact@tuist.dev)，並提供你的帳戶名稱、平台和預期平行工作量。我們將檢視所需容量並協助提高限制。

## 網路存取 {#network-access}

作業可以開啟連往公共網際網路的出站連線。私有位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）已被封鎖，且 runner 不接受任何入站連線。

| 平台 | 出站通訊埠 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 和 443 (HTTPS)，以及 DNS |
| macOS | 所有通訊埠 |

SSH 涵蓋 `git@` 相依性、SSH 子模組、部署金鑰，以及 `ssh` 或 `scp` 部署。如果 Linux 工作流程需要其他出站通訊埠，請[聯絡我們](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在機群上執行你的第一個作業。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接你的叢集，以 Tuist 設定檔命名佇列，並從步驟中將其設為目標。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連接 GitLab 一次，並使用流水線標籤選擇每個作業的機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="設定檔"
    details="選擇平台、大小和 Xcode 版本，使用你從作業中參考的具名機器設定檔。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="快取磁碟區"
    details="在作業之間保留 Xcode、模組和 Gradle 快取以及任何其他目錄，每次執行都有私人的可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## 為何選擇 Tuist Runners {#why-tuist-runners}

大多數 CI runner 供應商透過提供更強大的機器和持久性快取（通常是掛載回 CI 執行中的共用磁碟區）來加快作業速度。這確實有幫助，但磁碟區只是磁碟：它會保留先前 CI 執行所留下的任何內容。它不會複製以保持最新構件靠近建置執行處，也永遠無法到達程式碼建置的其他地方。

建置不再發生在單一位置。相同的程式碼會在開發人員的筆記型電腦、CI 環境，以及越來越多的編碼代理程式和其他自動化環境中編譯。Tuist Runners 的不同之處在於，它們共用所有這些環境已經讀取和寫入的相同<.localized_link href="/guides/features/cache">快取</.localized_link>，無論你使用哪種建置系統。隊友在筆記型電腦上預熱的構件、代理程式產生的構件，或先前建置留下的構件，都會在 runner 上命中，反之亦然。沒有單獨的 CI 快取需要預熱，且加速效果不限於 CI。

除此之外，快取與 runner 位於同一個私有網路上共置，因此快取讀寫保持在內部並靠近運算資源，而不是跨越公共網際網路。

總結如下：

- **跨所有環境共用。** Runner 會讀取和寫入與你的開發人員機器、CI 及編碼代理程式相同的快取，因此在任何地方完成的工作都會預熱各處的快取。
- **與運算資源共置。** 快取流量停留在 runner 旁的內部網路上，而非經過公共入口。
- **單一系統，非外加元件。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link> 和 <.localized_link href="/guides/features/build-insights">建置洞察</.localized_link> 都針對同一個專案和帳戶執行，因此 runner 不是獨立的建置數據孤島。
