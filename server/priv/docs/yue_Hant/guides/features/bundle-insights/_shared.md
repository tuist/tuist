## 標籤 {#tags}

上傳套件時附加標籤，以區分建置變體、環境或發布渠道。套件標籤遵循與 Build Insights 標籤相同的慣例：

```bash
tuist inspect bundle App.ipa --tags paid production
```

在 CI 中，你也可以使用 `TUIST_BUNDLE_TAGS` 設定以逗號分隔的標籤：

```bash
TUIST_BUNDLE_TAGS="paid,production" tuist inspect bundle App.ipa
```

明確指定的 `--tags` 會取代環境變數中的標籤。標籤可以包含字母、數字、連字號和底線，每個套件最多 10 個標籤，每個標籤最多 50 個字元。Android 套件也適用相同選項。`--json` 僅限本機使用，不會上傳標籤或套件。

標籤會顯示在套件名稱旁邊及套件詳細資料中。使用儀表板的 **標籤** 篩選器並輸入標籤，以在套件清單中包含或排除該標籤。比對為精確且區分大小寫，即使篩選運算子標示為 **包含** 和 **不包含**：`paid` 不會比對 `paid-extra`。若要從 CLI 進行篩選：

```bash
tuist bundle list --tags paid production
```

CLI、API（`?tags=paid,production`）和 MCP `list_bundles` 工具（`tags: ["paid", "production"]`）會傳回包含 **所有** 指定標籤的套件。API 上傳接受 `bundle.custom_metadata.tags`；清單和詳細資料回應則傳回 `custom_metadata.tags`。現有未帶標籤的套件仍如常可用。標籤只會篩選套件清單；不會影響大小圖表或自動比較與閾值基準。

現有用戶端可以繼續上傳和讀取不帶標籤的套件。更新後的用戶端也可以讀取省略 `custom_metadata` 的舊版伺服器回應。儲存和篩選標籤需要支援套件標籤的伺服器版本：舊版伺服器會忽略上傳中繼資料並拒絕標籤篩選。當未提供標籤時，更新後的用戶端會省略上傳中繼資料和標籤查詢參數。

## 了解套件大小 {#understanding-sizes}

對於每個已分析的套件，Tuist 會報告兩個值：

- **安裝大小**：應用程式安裝到裝置後所佔用的空間。
- **下載大小**：使用者下載的壓縮大小。對於 Apple 套件，這僅針對 `.ipa`（封存檔的大小）報告；對於 `.xcarchive` 或 `.app` 輸入則無法提供。

大小以位元組儲存，並使用十進位慣例顯示，其中 1 MB 為 1,000,000 位元組，1 GB 為 1,000,000,000 位元組——與 Apple 用於報告儲存容量和應用程式大小的慣例相同（請參閱 [Apple 裝置如何測量儲存容量](https://support.apple.com/en-us/102119)）。733,446,863 位元組的安裝大小會顯示為 733.4 MB。

## 持續整合 {#continuous-integration}

若要追蹤隨時間變化的套件大小，請在 CI 上分析套件。首先，確保你的 CI 已 <.localized_link href="/guides/server/authentication#continuous-integration">通過驗證</.localized_link>。

Tuist 也需要知道要將套件報告給哪個專案。如果你尚未連接專案，請執行 `tuist init`，或自行宣告 handle：

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

對於沒有 Swift manifest 的專案（例如 Gradle 專案），請使用 <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link>。當兩個檔案都存在時，`Tuist.swift` 具有優先權。

GitHub Actions 工作流程範例：

::: code-group
```yaml [Apple]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
```yaml [Android]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        # .aab is recommended over .apk for more accurate size analysis
        run: tuist inspect bundle App.aab
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
<!-- -->
:::

設定完成後，你可以查看套件大小隨時間的變化：

![套件大小圖表](/images/guides/features/bundle-size/bundle-size-graph.png)

## Pull/Merge Request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要 Git forge 整合**
>
> 若要取得自動的 pull/merge request 評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 專案</.localized_link> 與 Git forge 整合：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 或 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。

一旦你的 Tuist 專案與 Git 平台（例如 [GitHub](https://github.com)）連接，每當你執行 `tuist inspect bundle` 時，Tuist 就會直接在你的 pull/merge requests 中發佈評論：

![帶有已檢查套件的 GitHub app 評論](/images/guides/features/bundle-size/github-app-with-bundles.png)

## 大小閾值 {#size-thresholds}

> [!WARNING]
> **需要 Git forge 整合**
>
> 若要使用大小閾值，請將 [Tuist GitHub App](https://github.com/apps/tuist) 連接到你的專案。你可以從專案的整合頁面進行此操作。

大小閾值允許你在套件大小相對於基準分支增加超過設定的百分比或絕對大小時封鎖 pull requests。當違反閾值時，Tuist 會在 PR commit 上建立 GitHub Check Run，直到解決大小增加問題前都會封鎖合併：

![顯示套件大小閾值超出的 PR 狀態檢查](/images/guides/features/bundle-size/github-pr-check-status.png)

檢查運行會顯示基準大小、目前大小以及以設定單位表示的變化。如果增加是故意的，你可以透過點擊 **接受** 按鈕直接從 GitHub UI 接受它：

![顯示閾值違規的 GitHub 檢查運行](/images/guides/features/bundle-size/github-check-run-threshold.png)

### 設定 {#size-thresholds-configuration}

若要設定閾值，請前往專案的 **設定 > 套件** 標籤頁：

![套件大小閾值設定](/images/guides/features/bundle-size/bundle-size-thresholds.png)

選擇 **安裝大小** 或 **下載大小**，然後選擇 **閾值類型**：

- **百分比 (%)**：限制相對於基準大小的增長。支援小數百分比，例如 `0.47`。現有的百分比閾值會保留其設定的值和行為。
- **絕對大小 (MB)**：以固定數量限制增長，與基準大小無關。輸入 `1.5` 以允許最多 1.5 MB 的增長。MB 使用十進位單位：1 MB = 1,000,000 位元組。值必須解析為正的整數位元組數。

![絕對套件大小增長閾值設定](/images/guides/features/bundle-size/absolute-size-threshold.png)

兩種類型都會與設定的 **基準分支** 上最新且名稱相同、套件類型相同（例如 `.app` 或 `.ipa`）並至少有一個共同平台的套件進行比較，因此模擬器 `.app` 只會與模擬器 `.app` 上傳進行比較。可選的 **套件名稱** 會將規則限制於該套件。僅當增長 **超過** 限制時檢查才會失敗；增長相等、大小不變或減少則通過。若沒有匹配的基準或所選指標沒有記錄的大小，則會跳過該規則。絕對限制支援零大小的基準；百分比限制會繼續跳過它，因為百分比增長未定義。

### 限制誰可以接受 {#size-thresholds-approvals}

預設情況下，任何擁有儲存庫寫入權限的人都可以接受大小增加，因為 GitHub 就是向這些人顯示按鈕。若要縮小範圍，請在 **設定 > 套件** 下設定 **誰可以接受**：

- **任何人**：預設值。任何擁有儲存庫寫入權限的人。
- **選定的 GitHub 用戶**：僅限你添加的 GitHub 用戶名。

不在清單上的人會導致檢查失敗並附上解釋，而按鈕仍會顯示給可以使用它的人。
