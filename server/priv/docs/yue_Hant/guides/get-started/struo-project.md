---
{
  "title": "Struo 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將 Struo 連接至 Tuist，以實現共用快取、即時構建與測試洞察、測試分片以及應用程式預覽。"
}
---
# Struo 專案 {#struo-project}

<a id="once-project"></a>

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/struo-project
```

:::

[Struo](https://struo.run) 執行可快取的指令碼與建置圖。將其連接至 Tuist，即可跨機器共用快取成果、即時追蹤執行狀態，並發布應用程式供團隊試用。保留現有的專案原始碼與建置定義；整合設定位於 `struo.toml`。

## 必要條件

- 已安裝 [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 或更新版本，並具備工作區或可快取的指令碼。請參閱 [安裝指南](https://struo.run/docs/guide/getting-started)，或使用 mise 固定版本：

  ```bash
  mise use -g github:tuist/struo@1.0.0
  ```

- Tuist 帳號。Struo 整合不需要 Tuist CLI。

## 從 Once 升級 {#upgrading-from-once}

Struo 是 Once 的新名稱。將 `once.toml` 檔案重新命名為 `struo.toml`，將 mise 的固定來源從 `github:tuist/once` 更新為 `github:tuist/struo`，並將 `once` 指令替換為 `struo`。將指令碼標頭從 `# once` 更新為 `# struo`，並將 shebang 更新為 `#!/usr/bin/env -S struo exec -- bash`。將 `ONCE_*` 環境變數重新命名為 `STRUO_*`，例如 `STRUO_CACHE_PROVIDER`；Tuist 憑證仍使用 `TUIST_TOKEN`。

將忽略檔案中的 `.once/` 項目改為 `.struo/`。輸出現在位於 `.struo/out/`，而共用的本機內容快取使用 `$XDG_CACHE_HOME/struo/cas`（預設為 `~/.cache/struo/cas`）。快取金鑰與本機儲存空間採用新名稱，因此升級後本機快取會處於冷啟動狀態，而非遷移舊快取項目。請使用 `struo auth login --provider tuist` 再次登入。

重新命名不會改變 Tuist 的相容端點：即時回報仍使用 `once.events.v1`，現有的 `/api/.../once` 路由繼續支援。請參閱 [上游重新命名指南](https://struo.run/changelog/2026-11-18-once-is-now-struo)。

## 連接專案 {#connect-the-project}

從你的儲存庫根目錄執行：

```bash
struo connect --provider tuist --create
```

Struo 會在需要時為你登入，於你的個人帳號下建立 Tuist 專案，並將提供者繫結寫入 `struo.toml`。如需選擇其他帳號或現有專案，請參閱 [連接專案](https://struo.run/docs/guide/infrastructure/connect)。

對於現有的 Tuist 專案，請自行設定提供者與快取繫結：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

將 `acme` 和 `app` 替換為你的帳號與專案代號，然後進行驗證：

```bash
struo auth login --provider tuist
```

提交 `struo.toml`，讓隊友與 CI 共用目的地設定，而非你的憑證。每位開發者需在自己的機器上登入。

## 共用快取

本機快取只對填入該快取的機器有幫助。設定 Tuist 後，Struo 可以還原由其他開發者或 CI 產生的相符結果，避免重複執行相同工作。

照常執行你的可快取指令碼或圖目標：

```bash
struo build MyApplication
```

在儀表板中開啟 **Struo Cache** 以檢視遠端快取活動。如需設定與跨機器重用檢查，請參閱 <.localized_link href="/guides/features/cache/struo">Struo 快取</.localized_link>。

## 建置洞察

Struo 會在執行開始時列印儀表板連結。開啟該連結可在執行期間追蹤圖形、動作狀態與快取決策。使用 **Builds** 比較本機與 CI 效能，並調查失敗的動作。保留 CI 日誌以取得完整的程序輸出；目前不提供原始動作日誌匯入。

如需了解記錄內容以及如何從編碼代理程式或 Grafana 存取，請參閱 <.localized_link href="/guides/features/build-insights/struo">Struo 建置洞察</.localized_link>。

## 測試洞察與分片

執行你的 Struo 測試目標：

```bash
struo test
```

開啟 **Tests** 以檢視回報的套件、案例、持續時間與失敗。結果取決於測試目標的回報能力；執行測試程序的動作不會自動產生每個案例的測試報告。

當套件規模超出單一機器負荷時，建立託管分片計畫，並將其批次分散至 CI 工作節點。請參閱 <.localized_link href="/guides/features/test-insights/struo">Struo 測試洞察</.localized_link> 與 <.localized_link href="/guides/features/test-sharding/struo">Struo 測試分片</.localized_link>。

## 預覽與套件大小

為同一提供者新增構件繫結，以發布受支援的 Android、Apple 模擬器與 macOS 應用程式：

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
struo artifact publish MyApplication --track review
```

返回的連結會開啟你專案的預覽；處理可能需要一點時間。如需簽署要求與建置後的選用發布，請參閱 <.localized_link href="/guides/features/previews/struo">Struo 預覽</.localized_link>。

若要追蹤套件大小，請針對已建置的 `.app`、`.ipa`、`.xcarchive`、`.apk` 或 `.aab` 單獨使用 Tuist CLI。請遵循 <.localized_link href="/guides/features/bundle-insights">Apple 或 Android 套件洞察指南</.localized_link>；發布 Struo 構件不會自動上傳套件大小報告。

## 持續整合

在 `TUIST_TOKEN` 中使用獲授權執行專案操作的帳號權杖，或透過支援的 CI 提供者的 OpenID Connect 身分進行驗證：

```bash
struo auth login --provider tuist --no-browser
struo build MyApplication
struo test
```

在 GitHub Actions 上，為作業授予 `id-token: write` 與 `contents: read`。如需範例，請參閱 <.localized_link href="/guides/integrations/continuous-integration#struo">Struo 於持續整合</.localized_link>。個人開發者登入並非 CI 憑證。

## 遠端執行

啟用遠端執行的帳號也可以在 Tuist 的 Linux 工作節點上執行符合資格的圖命令動作。這與共用快取結果以及執行整個 CI 工作流程不同。如需工作節點需求與設定，請參閱 <.localized_link href="/guides/features/runners/struo">Struo 遠端執行</.localized_link>。
