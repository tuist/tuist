---
{
  "title": "Once 項目",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將 Once 連接至 Tuist，以使用共享快取、即時構建與測試洞察、測試分片及應用程式預覽。"
}
---
# Once 專案 {#once-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/once-project
```

:::

[Once](https://buildonce.dev) 會執行可快取的指令碼和建置圖。將它連接至 Tuist，即可跨機器共用已快取的工作、即時追蹤執行狀態，並發布應用程式供團隊試用。保留你現有的專案原始碼和建置定義；整合設定位於 `once.toml`。

## 必要條件

- 已安裝 [Once](https://buildonce.dev/docs/guide/getting-started)，並具備工作區或可快取的指令碼。
- 一個 Tuist 帳戶。Once 整合不需要 Tuist CLI。

## 連接專案 {#connect-the-project}

從你的儲存庫根目錄執行：

```bash
once connect --provider tuist --create
```

Once 會在需要時為你登入，於你的個人帳戶下建立 Tuist 專案，並將提供者繫結寫入 `once.toml`。請參閱 [連接專案](https://buildonce.dev/docs/guide/infrastructure/connect) 以選擇其他帳戶或現有專案。

對於現有的 Tuist 專案，請自行設定提供者和快取繫結：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

將 `acme` 和 `app` 替換為你的帳戶和專案代號，然後進行驗證：

```bash
once auth login --provider tuist
```

提交 `once.toml`，讓你的隊友和 CI 共用目的地設定，而非你的憑證。每位開發者需在自己的機器上登入。

## 共用快取

本機快取只對產生該快取的機器有幫助。設定好 Tuist 後，Once 可以還原由其他開發者或 CI 產生的相符結果，而無需重新執行相同工作。

如常執行你的可快取指令碼或圖目標：

```bash
once build MyApplication
```

在儀表板中開啟 **Once Cache** 以檢視遠端快取活動。請參閱 <.localized_link href="/guides/features/cache/once">Once 快取</.localized_link> 了解設定方法及跨機器重用檢查。

## 建置洞察

Once 會在執行開始時印出儀表板連結。開啟它以在執行期間追蹤圖、動作狀態和快取決策。使用 **Builds** 比較本機和 CI 效能，並調查失敗的動作。保留 CI 日誌以獲取完整的程序輸出；目前不支援原始動作日誌匯入。

請參閱 <.localized_link href="/guides/features/build-insights/once">Once 建置洞察</.localized_link> 了解記錄內容，以及如何從編碼代理程式或 Grafana 存取。

## 測試洞察與分片

執行你的 Once 測試目標：

```bash
once test
```

開啟 **Tests** 以檢視報告的套件、用例、持續時間和失敗情況。結果取決於測試目標的報告能力；執行測試程序的動作不會自動產生每用例的測試報告。

當套件規模超出單一機器負荷時，建立託管分片計劃，並將其批次分發到 CI 工作節點。請參閱 <.localized_link href="/guides/features/test-insights/once">Once 測試洞察</.localized_link> 和 <.localized_link href="/guides/features/test-sharding/once">Once 測試分片</.localized_link>。

## 預覽與套件大小

向同一提供者新增構件繫結，以發布支援的 Android、Apple 模擬器和 macOS 應用程式：

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
once artifact publish MyApplication --track review
```

返回的連結會開啟你專案的預覽；處理可能需要一點時間。請參閱 <.localized_link href="/guides/features/previews/once">Once 預覽</.localized_link> 了解簽署要求和建置後的可選發布選項。

若要追蹤套件大小，請針對已建置的 `.app`、`.ipa`、`.xcarchive`、`.apk` 或 `.aab` 單獨使用 Tuist CLI。請遵循 <.localized_link href="/guides/features/bundle-insights">Apple 或 Android 套件洞察指南</.localized_link>；發布 Once 構件不會自動上傳套件大小報告。

## 持續整合

在 `TUIST_TOKEN` 中使用獲授權執行專案操作的帳戶權杖，或透過支援的 CI 提供者的 OpenID Connect 身分進行驗證：

```bash
once auth login --provider tuist --no-browser
once build MyApplication
once test
```

在 GitHub Actions 上，授予作業 `id-token: write` 和 `contents: read` 權限。請參閱 <.localized_link href="/guides/integrations/continuous-integration#once">Once 於持續整合</.localized_link> 獲取範例。個人開發者登入並非 CI 憑證。

## 遠端執行

啟用遠端執行的帳戶也可以在 Tuist 的 Linux 工作節點上執行符合條件的圖命令動作。這與共用快取結果以及執行整個 CI 工作流程不同。請參閱 <.localized_link href="/guides/features/runners/once">Once 遠端執行</.localized_link> 了解工作節點需求和設定。
