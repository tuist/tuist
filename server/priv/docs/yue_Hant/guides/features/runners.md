---
{
  "title": "Runners",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 係為 GitHub Actions、Buildkite、GitLab CI 同 Bitrise 提供嘅托管 macOS 同 Linux runner，配備與運算資源共置並同你本地機器共享嘅快取。"
}
---
# 執行器 {#runners}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前仍為僅限邀請，因為我哋正擴展容量。[聯絡我哋](mailto:contact@tuist.dev)或喺 [社區 Slack](https://slack.tuist.dev) 上通知我哋，為你嘅帳戶申請存取權。當 Runners 正式開放時，我哋會公佈定價。


Tuist Runners 係專為你嘅 GitHub Actions、Buildkite、GitLab CI 同 Bitrise 流程提供嘅受管 macOS 同 Linux 執行器。你唔使喺 CI 供應商嘅託管機器上運行作業，而係將作業指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，佢就會喺 Tuist 嘅機群上運行，同你團隊已經使用緊嘅同一個 <.localized_link href="/guides/features/cache">快取</.localized_link> 並排，無需安裝任何執行器代理程式，亦無需維護基礎設施。要計算轉換機器前咩因素影響你嘅 CI 賬單，請參閱 [CI 成本](https://tuist.dev/solutions/ci-costs)。

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

Linux 執行器預設透過 `/dev/kvm` 提供硬體加速虛擬化。使用你平常嘅 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）來運行 x86_64 Android 模擬器，包括 Gradle Managed Devices。訪問設備無需特殊嘅執行器設定檔、KVM 設定動作、權限更改或 `sudo`。

執行器映像包含 Android SDK。喺啟動設備之前，請安裝模擬器及其運行時庫。對於已定義名為 `pixel6` 嘅 Gradle Managed Device 嘅項目，GitHub Actions 作業如下所示：

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

使用你嘅 Android Gradle Plugin 所需嘅 Java 版本，並將測試任務替換為你項目中嘅 managed-device 任務。配置一個 **x86_64** 系統映像。選擇一個有足夠記憶體供 Gradle 同模擬器使用嘅執行器規格；併發設備會共享作業嘅 CPU 同記憶體分配。

以普通執行器用戶身份運行模擬器。此示例中嘅 `sudo` 僅用於安裝操作系統軟件包。

模擬器使用嵌套虛擬化，因此其計時可能與實體 Android 設備不同。請將模擬器基準測試視為對該 CI 環境嘅測量，而非實體設備性能。

## 併發限制 {#concurrency-limits}

每個帳戶對於 macOS 同 Linux 都有獨立嘅 vCPU 同記憶體併發限制。喺 Tuist 接受作業之前，它會檢查作業嘅 <.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link> 與該平台上當前運行嘅所有作業進行對比。只有當作業嘅 vCPU 同記憶體都符合剩餘容量時，作業才會開始；否則，它會保持排隊狀態，直到容量可用。喺一個平台上嘅工作永遠不會消耗另一個平台嘅容量。

Air 帳戶具有固定嘅併發限制。對於 Pro 同 Enterprise 帳戶，Tuist 會根據經常性使用情況以及最近無法與活躍執行器並存嘅排隊工作，自動增加緩衝空間。自動調整只會增加限制：現有配額同合約規定嘅最低容量會得到保留。增長係漸進嘅，並受安全上限約束，因此突然激增不會授予無限併發。較高嘅帳戶限制並不能保證立即有可用機器。

Runners 儀表板中嘅 **併發** 部分顯示每小時峰值允許嘅 vCPU 同記憶體使用量，並以階梯線顯示每小時開始時已知嘅限制。紅色條形達到該歷史閾值；它們本身並不能證明作業曾等待。一小時內嘅增加可能會使其峰值高於桶起始線。當前限制顯示喺每個圖表旁邊。歷史追蹤開始之前嘅時期沒有限制線，而唔係假設嘅歷史值。

如果工作流程繼續喺安全上限處排隊，請 [聯絡我哋](mailto:contact@tuist.dev)，提供你嘅帳戶名稱、平台同預期並行工作量，以便我哋審查所需容量。

## 網絡訪問 {#network-access}

作業可以打開到公共互聯網嘅出站連接。私有地址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）被阻止，且執行器不接受任何入站連接。

| 平台 | 出站端口 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 同 443 (HTTPS)，加上 DNS |
| macOS | 所有端口 |

SSH 涵蓋 `git@` 依賴項、SSH 子模組、部署金鑰以及 `ssh` 或 `scp` 部署。如果 Linux 工作流程需要其他出站端口，請 [聯絡我哋](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，然後喺機群上運行你嘅第一個作業。"
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
    details="連接你嘅工作區，並喺 Tuist 設定檔上運行你自託管執行器池嘅構建。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="通過一個請求從你自己嘅 git 倉庫或協調器運行作業，並通過 webhooks 跟蹤它們。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="設定檔"
    details="通過你喺作業中引用嘅命名機器設定檔，選擇平台、大小同 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="映像"
    details="查看 macOS 同 Linux 執行器上預裝咩：Xcode、模擬器、Metal 工具鏈、Docker、Android SDK 等。"
    link="/guides/features/runners/images"
/>
  <.home_card
    title="快取磁碟區"
    details="喺作業之間保留 Xcode、模組同 Gradle 快取，以及任何其他目錄，每次運行都有獨立可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo 圖表動作 {#struo-graph-actions}

<a id="once-graph-actions"></a>

當帳戶啟用遠端執行且伺服器宣傳相容嘅工作節點能力時，Struo 可以喺 Tuist 嘅 Linux 工作節點上執行符合資格嘅圖表指令動作。呢種係動作層級執行，同上面提到嘅 CI 供應商作業分開。請參閱 <.localized_link href="/guides/features/runners/struo">Struo 遠端執行</.localized_link> 以了解設定、映像要求同相容性檢查。

## 點解要用 Tuist Runners {#why-tuist-runners}

大多數 CI 執行器供應商通過提供更強大嘅機器同持久化快取（通常係掛載返去你 CI 運行中嘅共享磁碟區）嚟加快作業速度。這雖然有幫助，但磁碟區只係一塊磁碟：它會攜帶之前 CI 運行遺留嘅任何內容。它並唔會複製以保持最新構建產物靠近構建運行位置，亦都無法觸及你代碼被構建嘅其他地方。

構建唔再只發生喺一個地方。相同嘅代碼會喺開發者筆記本電腦、跨 CI，以及越來越多由編碼代理同其他自動化環境中編譯。Tuist Runners 唔同之處在於，無論你使用咩構建系統，它們都共享所有這些環境已經讀取同寫入嘅同一個 <.localized_link href="/guides/features/cache">快取</.localized_link>。隊友喺筆記本電腦上預熱嘅產物、代理生成嘅產物，或者早期構建留下嘅產物，都會喺執行器上命中，反之亦然。無需單獨預熱 CI 快取，加速效果亦都唔局限於 CI。

除此之外，快取同執行器位於同一私有網絡上，因此快取讀寫保持喺內部並靠近計算資源，而唔係穿越公共互聯網。

綜合嚟講：

- **跨所有環境共享。** 執行器讀寫同你開發機器、CI 同編碼代理相同嘅快取，因此喺任何地方完成嘅工作都會預熱 everywhere 嘅快取。
- **與計算資源共存。** 快取流量停留喺執行器旁邊嘅內部網絡，而唔係經過公共入口。
- **單一系統，非附加組件。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link> 同 <.localized_link href="/guides/features/build-insights">構建洞察</.localized_link> 都針對同一項目同帳戶運行，因此執行器唔係獨立嘅構建數據孤島。
