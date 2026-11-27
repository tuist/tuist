---
{
  "title": "快照",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "在 Xcode 和 Gradle 專案中捕捉視覺回歸問題：Tuist 會儲存你的快照圖片，將每個拉取請求與其基準進行比較，並讓你從儀表板或拉取請求中核准或拒絕變更。"
}
---
# 快照 {#snapshots}

> [!IMPORTANT]
> **僅限邀請**
>
> 快照功能目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在 [社群 Slack](https://slack.tuist.dev) 中聯繫我們，以請求開啟您帳戶的存取權限。

快照測試會將你的 UI 渲染為圖片，並與參考圖片進行比較，以捕捉視覺回歸問題。你不需要將這些參考圖片提交到儲存庫，而是將每次測試執行所渲染的圖片上傳至 Tuist。Tuist 會將其與**基準**進行比較，在儀表板中顯示變更內容，並在有人核准變更之前讓該次執行失敗。

- Git 中沒有參考圖片，因此檢出保持輕量，也無需處理 PNG 檔案的衝突。
- 審查者可以在程式碼旁邊查看變更：並排顯示、差異檢視，或使用滑動或洋蔥皮重疊效果。
- 變更可以在儀表板或拉取請求中核准或拒絕，一旦分支合併，該核准就會成為新的基準。

## 運作方式 {#how-it-works}

1. 你的測試會渲染圖片，例如每個 SwiftUI 或 Compose 預覽。
2. Tuist CLI 或 Gradle 外掛程式會將它們作為目前提交的**快照建置**上傳。
3. Tuist 會選擇基準：你的預設分支在你分支起始提交時的建置。
4. 每張圖片都會與其基準進行比較，並標記為已變更、新增、移除或未變更。
5. 建置會獲得一個判定結果：

| 判定結果 | 執行 | 時機 |
| --- | --- | --- |
| 基準 | 通過 | 該建置來自預設分支，因此後續建置會以其作為比較對象。 |
| 已通過 | 通過 | 沒有圖片變更或被移除。新圖片無需審查。 |
| 需要審查 | 失敗 | 圖片已變更或被移除，且尚未有人審查。 |
| 已核准 | 通過 | 有人已核准變更。 |
| 已拒絕 | 失敗 | 有人已拒絕變更。 |

建置會在一個**集合**內進行比較，例如 `ios-iphone` 或 `android-phone`。每個裝置設定使用一個集合，這樣不同尺寸渲染的圖片就不會相互比較。

## 設定 {#set-up}

為你的專案選擇整合方式：

<.home_cards>
  <.home_card
    title="Xcode"
    details="使用 tuist xcodebuild test 對 Xcode 專案中的每個 SwiftUI 預覽進行快照。"
    link="/guides/features/snapshots/xcode"
/>
  <.home_card
    title="產生的專案"
    details="使用 tuist test 對 Tuist 產生的專案中的每個 SwiftUI 預覽進行快照。"
    link="/guides/features/snapshots/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="使用 Tuist Gradle 外掛程式，對每個 Compose 預覽進行快照，或上傳 Paparazzi 和 Roborazzi 記錄的內容。"
    link="/guides/features/snapshots/gradle"
/>
</.home_cards>

## 在儀表板中審查變更 {#dashboard}

每個快照建置在你的專案儀表板的 **測試 → 快照** 下都有一個頁面。它顯示建置的判定結果、分支、提交、拉取請求和基準，並按狀態和群組列出圖片。使用 **核准變更** 或 **拒絕變更** 來審查建置。你可以稍後更改審查結果。

![需要審查的快照建置，變更的圖片與其基準並排顯示](/images/guides/features/snapshots/review.png)

在 **並排**、**差異**（突出顯示變更的像素）、**滑動**（在基準和新圖片之間滑動）以及 **洋蔥皮**（將一張圖片淡入另一張）之間切換。每張圖片都可以全螢幕開啟。

![滑動模式，在基準和新圖片之間滑動](/images/guides/features/snapshots/wipe.png)

## 在拉取請求中審查變更 {#pull-request}

安裝 <.localized_link href="/guides/integrations/gitforge/github">GitHub 應用程式</.localized_link> 後，拉取請求的每個快照建置都會獲得一個名為 `tuist/snapshots (<set>)` 的檢查。當變更需要審查，或審查者拒絕變更後，如果該檢查是必需的，則會失敗並阻止合併：

![拉取請求的合併方塊，由於變更被拒絕，快照檢查失敗](/images/guides/features/snapshots/github-pr-checks.png)

該檢查會統計集合中已變更、新增和移除的圖片數量，並連結到儀表板中的建置。你可以在不離開 GitHub 的情況下，從檢查頁面核准或拒絕變更。檢查會更新審查者的姓名，且被拒絕的建置稍後仍可被核准。

![變更被拒絕後 GitHub 上的快照檢查，帶有核准按鈕](/images/guides/features/snapshots/github-check-run.png)

核准不會重新執行你的測試：它會讓檢查通過。只要同一分支的後續建置具有完全相同的變更，就會保留核准狀態，因此重新執行 CI 或推送未觸及已審查圖片的提交也會通過。對圖片的任何其他變更都需要新的審查。一旦分支合併，預設分支的建置就會成為新的基準。
