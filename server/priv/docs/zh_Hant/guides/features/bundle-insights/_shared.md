## 了解套件大小 {#understanding-sizes}

針對每個分析的套件，Tuist 會回報兩個數值：

- **安裝大小**：應用程式安裝到裝置後所佔用的空間。
- **下載大小**：使用者下載的壓縮大小。Apple 套件僅針對 `.ipa`（封存檔的大小）回報此數值；若輸入為 `.xcarchive` 或 `.app`，則無法提供。

大小以位元組儲存，並使用十進位慣例顯示，其中 1 MB 等於 1,000,000 位元組，1 GB 等於 1,000,000,000 位元組——這與 Apple 回報儲存空間和應用程式大小的慣例相同（請參閱 [Apple 裝置如何測量儲存容量](https://support.apple.com/en-us/102119)）。733,446,863 位元組的安裝大小會顯示為 733.4 MB。

## 持續整合 {#continuous-integration}

若要追蹤隨時間變化的套件大小，請在 CI 上分析套件。首先，請確保你的 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">通過驗證</.localized_link>。

Tuist 也需要知道要將套件回報至哪個專案。如果你尚未連接專案，請執行 `tuist init`，或自行宣告 handle：

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

## Pull/Merge Request 留言 {#pullmerge-request-comments}

> [!WARNING]
> **需要與 Git 平台整合**
>
> 若要自動取得拉取請求或合併請求的評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 專案</.localized_link>與 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link>整合。

一旦你的 Tuist 專案與 Git 平台（例如 [GitHub](https://github.com)）連接，每當你執行 `tuist inspect bundle` 時，Tuist 就會直接在 pull/merge request 中張貼留言：

![包含已檢查套件的 GitHub App 留言](/images/guides/features/bundle-size/github-app-with-bundles.png)

## 大小閾值 {#size-thresholds}

> [!WARNING]
> **需要與 Git Forge 整合**
>
> 若要使用大小閾值，請將 [Tuist GitHub App](https://github.com/apps/tuist) 連接至你的專案。你可以在專案的整合頁面進行此操作。

大小閾值可讓你在套件大小相對於基準分支增加超過設定的百分比或絕對大小時封鎖 pull request。當違反閾值時，Tuist 會在 PR commit 上建立 GitHub Check Run，並在解決大小增加問題之前封鎖合併：

![顯示套件大小閾值超出的 PR 狀態檢查](/images/guides/features/bundle-size/github-pr-check-status.png)

檢查執行會顯示基準大小、目前大小以及以設定單位表示的變化。如果增加是故意的，你可以直接在 GitHub UI 中點擊 **接受** 按鈕來接受：

![顯示閾值違規的 GitHub 檢查執行](/images/guides/features/bundle-size/github-check-run-threshold.png)

### 設定 {#size-thresholds-configuration}

若要設定閾值，請前往專案的 **設定 > 套件** 分頁：

![套件大小閾值設定](/images/guides/features/bundle-size/bundle-size-thresholds.png)

選擇 **安裝大小** 或 **下載大小**，然後選擇 **閾值類型**：

- **百分比 (%)**：限制相對於基準大小的成長。支援小數百分比，例如 `0.47`。現有的百分比閾值會保留其設定的數值和行為。
- **絕對大小 (MB)**：以固定金額限制成長，與基準大小無關。輸入 `1.5` 以允許最多 1.5 MB 的成長。MB 使用十進位單位：1 MB = 1,000,000 位元組。數值必須解析為正的整數位元組數。

![絕對套件大小成長閾值設定](/images/guides/features/bundle-size/absolute-size-threshold.png)

兩種類型都會與設定的 **基準分支** 上最新的套件進行比較，該套件需具有相同的名稱、相同的套件類型（例如 `.app` 或 `.ipa`），以及至少一個共同的平台，因此模擬器 `.app` 只會與模擬器 `.app` 上傳進行比較。選用項目 **套件名稱** 會將規則限制在該套件。只有當成長 **超過** 限制時，檢查才會失敗；相等的成長、不變的大小和減少則會通過。如果沒有相符的基準或所選指標沒有記錄的大小，則會跳過該規則。絕對限制支援零大小的基準；百分比限制會繼續跳過它，因為百分比成長未定義。

### 限制誰可以接受 {#size-thresholds-approvals}

預設情況下，任何對儲存庫具有寫入權限的人都可以接受大小增加，因為 GitHub 會向他們顯示該按鈕。若要縮小範圍，請在 **設定 > 套件** 下設定 **誰可以接受**：

- **任何人**：預設值。任何對儲存庫具有寫入權限的人。
- **選定的 GitHub 使用者**：僅限你新增的 GitHub 使用者名稱。

不在清單上的人會使檢查失敗並附上說明，而按鈕會保留給可以使用它的人。
