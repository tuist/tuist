---
{
  "title": "Once 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將 Once 連接至 Tuist，以享用共用快取、即時建構與測試洞察、測試分片及應用程式預覽。"
}
---
# Once 專案 {#once-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/once-project
```

:::

[Once](https://buildonce.dev) 會執行可快取的指令碼同建構圖。將佢連接到 Tuist，就可以喺唔同機器之間共享快取工作、實時追蹤執行進度，並發布應用程式畀團隊試用。保留你現有的專案原始碼同建構定義；整合設定存放喺 `once.toml`。

## 前置要求

- 已安裝 [Once](https://buildonce.dev/docs/guide/getting-started)，並有一個工作區或可快取的指令碼。
- 一個 Tuist 帳戶。Once 整合唔需要 Tuist CLI。

## 連接專案 {#connect-the-project}

喺你嘅儲存庫根目錄，執行：

```bash
once connect --provider tuist --create
```

Once 會喺需要時幫你登入，喺你嘅個人帳戶底下建立一個 Tuist 專案，並將提供者綁定寫入 `once.toml`。請參閱 [連接專案](https://buildonce.dev/docs/guide/infrastructure/connect) 以選擇另一個帳戶或現有專案。

對於現有嘅 Tuist 專案，請自行設定提供者同快取綁定：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

將 `acme` 同 `app` 替換為你嘅帳戶同專案識別符，然後進行認證：

```bash
once auth login --provider tuist
```

提交 `once.toml`，令你嘅隊友同 CI 共享目的地設定，而唔係你嘅憑證。每位開發人員都喺自己嘅機器上登入。

## 共享快取

本地快取只對填充咗佢嘅機器有用。設定好 Tuist 之後，Once 可以還原由另一位開發人員或 CI 產生嘅匹配結果，而唔使重新執行相同工作。

如常執行你可快取嘅指令碼或圖目標：

```bash
once build MyApplication
```

喺儀表板開啟 **Once Cache** 以檢查遠端快取活動。請參閱 <.localized_link href="/guides/features/cache/once">Once 快取</.localized_link> 了解設定方法同跨機器重用檢查。

## 建構洞察

Once 會喺執行開始時印出儀表板連結。開啟它以追蹤圖結構、動作狀態同快取決策。使用 **Builds** 比較本地同 CI 效能，並調查失敗動作。保留 CI 日誌以獲取完整進程輸出；目前未提供原始動作日誌匯入功能。

請參閱 <.localized_link href="/guides/features/build-insights/once">Once 建構洞察</.localized_link> 了解記錄咗乜嘢數據，以及點樣從編碼代理或 Grafana 存取。

## 測試洞察同分片

執行你嘅 Once 測試目標：

```bash
once test
```

開啟 **Tests** 以檢查報告嘅測試套件、用例、持續時間同失敗情況。結果取決於測試目標嘅報告能力；執行測試進程嘅動作唔會自動生成逐用例測試報告。

當測試套件規模超出單台機器承受能力時，建立託管分片計劃，並將其批次分發到 CI 工作節點。請參閱 <.localized_link href="/guides/features/test-insights/once">Once 測試洞察</.localized_link> 同 <.localized_link href="/guides/features/test-sharding/once">Once 測試分片</.localized_link>。

## 預覽同捆綁包大小

向同一提供者添加構件綁定，以發布受支援嘅 Android、Apple 模擬器同 macOS 應用程式：

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
once artifact publish MyApplication --track review
```

返回嘅連結會打開你專案嘅預覽；處理可能需要少少時間。請參閱 <.localized_link href="/guides/features/previews/once">Once 預覽</.localized_link> 了解簽署要求同建構後可選發布選項。

要追蹤捆綁包大小，請針對已建構嘅 `.app`、`.ipa`、`.xcarchive`、`.apk` 或 `.aab` 單獨使用 Tuist CLI。請遵循 <.localized_link href="/guides/features/bundle-insights">Apple 或 Android 捆綁包洞察指南</.localized_link>；發布 Once 構件唔會自動上傳捆綁包大小報告。

## 持續整合

使用獲授權執行專案操作嘅帳戶令牌，放入 `TUIST_TOKEN`，或透過受支援 CI 提供者嘅 OpenID Connect 身份進行認證：

```bash
once auth login --provider tuist --no-browser
once build MyApplication
once test
```

喺 GitHub Actions 上，授予作業 `id-token: write` 同 `contents: read` 權限。請參閱 <.localized_link href="/guides/integrations/continuous-integration#once">Once 喺持續整合中</.localized_link> 獲取示例。個人開發者登入唔係 CI 憑證。

## 遠端執行

啟用遠端執行功能嘅帳戶，亦可以喺 Tuist 嘅 Linux 工作節點上運行符合條件嘅圖命令動作。這與共享快取結果同運行整個 CI 工作流程係分開嘅。請參閱 <.localized_link href="/guides/features/runners/once">Once 遠端執行</.localized_link> 了解工作節點要求同設定。
