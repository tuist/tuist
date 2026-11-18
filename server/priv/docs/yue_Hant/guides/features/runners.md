---
{
  "title": "Runners",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 係專為 GitHub Actions、Buildkite、GitLab CI 同 Bitrise 提供嘅受管 macOS 同 Linux 執行器，快取與運算資源並置，並可與你嘅本機共用。"
}
---
# Runners {#runners}

> [!IMPORTANT]
> **只限邀請**
>
> Tuist Runners 目前只限邀請，我哋正擴展容量。[聯絡我哋](mailto:contact@tuist.dev)或喺[社區 Slack](https://slack.tuist.dev)通知我哋，為你嘅帳戶申請存取權。當 Runners 全面開放時，我哋會公佈定價。


Tuist Runners 係專為你嘅 GitHub Actions、Buildkite、GitLab CI 同 Bitrise 流水線而設嘅受管 macOS 同 Linux runner。與其喺 CI 供應商嘅託管機器上執行作業，不如將作業指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，佢就會喺 Tuist 嘅機隊上運行，緊鄰你團隊已經使用嘅同一個<.localized_link href="/guides/features/cache">快取</.localized_link>，無需安裝 runner agent，亦無需維護基礎設施。想喺更換機器之前了解乜嘢驅動你嘅 CI 賬單，請參閱[CI 成本](https://tuist.dev/solutions/ci-costs)。

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

Linux runner 預設透過 `/dev/kvm` 提供硬件加速虛擬化。使用你平常嘅 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）來運行 x86_64 Android 模擬器，包括 Gradle Managed Devices。訪問設備無需特殊嘅 runner 設定檔、KVM 設置動作、權限變更或 `sudo`。

Runner 映像包含 Android SDK。喺啟動設備之前，請安裝模擬器及其運行時庫。對於已經定義咗名為 `pixel6` 嘅 Gradle Managed Device 嘅項目，GitHub Actions 作業如下所示：

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

使用你嘅 Android Gradle Plugin 所需嘅 Java 版本，並將測試任務替換為你項目嘅 managed-device 任務。配置 **x86_64** 系統映像。選擇一個有足夠內存供 Gradle 同模擬器使用嘅 runner 規格；並發設備會共享作業嘅 CPU 同內存分配。

以普通 runner 用戶身份運行模擬器。此示例中嘅 `sudo` 僅用於安裝操作系統軟件包。

模擬器使用嵌套虛擬化，因此其計時可能與實體 Android 設備不同。將模擬器基準測試視為對該 CI 環境嘅測量，而非實體設備性能。

## 並發限制 {#concurrency-limits}

每個帳戶對於 macOS 同 Linux 都有獨立嘅 vCPU 同內存並發限制。喺 Tuist 接納作業之前，它會檢查作業嘅 <.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link> 與該平台上當前運行嘅所有作業。只有當作業嘅 vCPU 同內存都適合剩餘容量時，作業才會開始；否則它會保持排隊狀態，直到有空閒容量。喺一個平台上嘅工作永遠不會消耗另一個平台嘅容量。

Air 帳戶有固定嘅並發限制。對於 Pro 同 Enterprise 帳戶，Tuist 會根據經常性使用情況同最近無法與活躍 runner 並行嘅排隊工作自動增加緩衝空間。自動調整只會增加限制：現有配額同合約最低容量會得到保留。增長係漸進嘅，並受安全上限約束，因此突然嘅激增不會授予無限並發。較高嘅帳戶限制並不保證機器立即可用。

Runners 儀表板嘅 **並發** 部分顯示每小時峰值接納嘅 vCPU 同內存使用量，並以階梯線顯示每小時開始時已知嘅限制。紅色條形達到咗該歷史閾值；它們本身並不能證明作業曾等待。一小時內嘅增加可能會使其峰值高於桶起始線。當前限制顯示喺每個圖表旁邊。歷史追蹤開始之前嘅時期沒有限制線，而唔係假設嘅歷史值。

如果工作流程繼續喺安全上限處排隊，請[聯絡我哋](mailto:contact@tuist.dev)，提供你嘅帳戶名稱、平台同預期嘅並行工作量，以便我哋審查所需容量。

## 網絡訪問 {#network-access}

作業可以打開到公共互聯網嘅出站連接。私有地址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）被阻止，並且 runner 不接受任何入站連接。

| 平台 | 出站端口 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 同 443 (HTTPS)，加上 DNS |
| macOS | 所有端口 |

SSH 涵蓋 `git@` 依賴項、SSH 子模塊、部署密鑰以及 `ssh` 或 `scp` 部署。如果 Linux 工作流程需要其他出站端口，請[聯絡我哋](mailto:contact@tuist.dev)。

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
    title="Bitrise"
    details="連接你嘅工作區，並喺 Tuist 設定檔上運行你自託管 runner 池嘅構建。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="通過一個請求從你自己嘅 git forge 或編排器運行作業，並通過 webhooks 跟蹤它們。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="設定檔"
    details="通過你喺作業中引用嘅具名機器設定檔，選擇平台、大小同 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="映像"
    details="查看 macOS 同 Linux runner 上預裝咗乜嘢：Xcode、模擬器、Metal 工具鏈、Docker、Android SDK 等等。"
    link="/guides/features/runners/images"
/>
  <.home_card
    title="快取卷"
    details="喺作業之間保留 Xcode、模組同 Gradle 快取以及任何其他目錄，每次運行都有專屬嘅可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Once 圖表動作 {#once-graph-actions}

當帳戶啟用遠程執行且伺服器宣傳兼容嘅工作節點能力時，Once 可以喺 Tuist 嘅 Linux 工作節點上執行符合資格嘅圖表命令動作。呢種係動作級別嘅執行，與上述 CI 提供商作業分開。請參閱 <.localized_link href="/guides/features/runners/once">Once 遠程執行</.localized_link> 以了解設置、映像要求同兼容性檢查。

## 點解選擇 Tuist Runners {#why-tuist-runners}

大多數 CI runner 提供商通過提供更強大嘅機器同持久化快取（通常係掛載回你 CI 運行中嘅共享卷）來加快作業速度。這有幫助，但卷只係磁盤：它會攜帶之前 CI 運行留下嘅任何內容。它不會被複製以將最新嘅構建產物保持在靠近構建運行嘅地方，而且它永遠無法到達你代碼構建嘅其他地方。

構建不再只發生喺一個地方。相同嘅代碼會喺開發人員筆記本電腦、CI 環境中編譯，並且越來越多地由編碼代理同其他自動化環境編譯。Tuist Runners 唔同之處在於，無論你使用乜嘢構建系統，它們都共享所有這些環境已經讀取同寫入嘅同一個 <.localized_link href="/guides/features/cache">快取</.localized_link>。隊友喺他們筆記本電腦上預熱嘅產物、代理生成嘅產物或早期構建留下嘅產物都會喺 runner 上命中，反之亦然。無需單獨預熱 CI 快取，加速效果亦不限於 CI。

除此之外，快取與 runner 位於同一私有網絡上，因此快取讀寫保持喺內部並靠近計算資源，而唔係穿越公共互聯網。

總結如下：

- **跨所有環境共享。** Runner 讀取同寫入嘅快取與你嘅開發機器、CI 同編碼代理相同，因此喺任何地方完成嘅工作都會預熱 everywhere 嘅快取。
- **與計算資源共存。** 快取流量停留喺 runner 旁邊嘅內部網絡上，而唔係通過公共入口。
- **單一系統，非附加組件。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link> 同 <.localized_link href="/guides/features/build-insights">構建洞察</.localized_link> 都針對同一項目同帳戶運行，因此 runner 唔係獨立嘅構建數據孤島。
