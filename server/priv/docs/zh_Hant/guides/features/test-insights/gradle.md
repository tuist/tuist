---
{
  "title": "Gradle 測試分析",
  "titleTemplate": ":title · 測試分析 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Gradle 測試分析資料，以監控測試效能。"
}
---
# Gradle 測試見解 {#gradle-test-insights}

> [!IMPORTANT]
> **必要條件**
>
> - 已套用 `dev.tuist` Gradle 外掛程式，如 <.localized_link href="/guides/get-started/gradle-project">開始使用 Gradle 專案</.localized_link> 中所述。

Tuist 的 Gradle 外掛程式會在每次測試任務執行後自動上傳測試結果，讓你能直接在 Tuist 儀表板中查看測試效能與不穩定測試。

一旦套用外掛程式，系統就會自動收集測試見解。無需額外設定。

你可以在 Tuist 儀表板中存取測試見解，並觀察其隨時間的變化：

![包含測試見解的儀表板](/images/guides/features/build-insights/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

此外掛程式會收集所有 Gradle `Test` 任務的結果，包括：
- 個別測試案例的通過／失敗狀態與持續時間
- 測試套件與類別結構
- 跨多次執行的不穩定測試偵測

開啟 <.localized_link href="/guides/features/test-code-coverage/gradle">程式碼涵蓋率</.localized_link> 以同時上傳測試所執行的程式碼。

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本機建置的測試結果會在背景上傳。
- CI 執行的測試結果會在前台上傳，以避免在短暫存活的代理程式上遺失遙測資料。

你可以使用 `uploadInBackground`（位於 `tuist` 區塊中）覆寫此行為，該區塊位於你的 `settings.gradle.kts`：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git 歷史記錄 {#git-history}

在 CI 上，此外掛程式於回報測試執行時也會上傳檢出區的提交歷史記錄：提交的 SHA、其父提交、提交日期，以及該執行與其拉取請求基礎分支所在的分支。不會上傳檔案內容、提交訊息或作者資訊。這能讓 Tuist 知道哪些提交已合併至你的預設分支，例如合併佇列所測試的提交。外掛程式會讀取檢出區已有的歷史記錄；若檢出區沒有基礎分支，則會向遠端查詢其最新提交（`git ls-remote`）。除程式碼涵蓋率外，它不會抓取歷史記錄。啟用程式碼涵蓋率時，系統會深化淺層檢出（不包含檔案內容），以找出拉取請求的分叉點並取得 Tuist 已擁有的提交，確保不會上傳缺少父提交的提交。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取檢出區，不會聯絡遠端。 |
| `TUIST_GIT_BRANCH=<branch>` | 為執行指定分支名稱，優先於 CI 供應商與檢出區提供的資訊。在 Tuist 無法識別、且檢出的是提交而非分支的 CI 系統上設定此變數，否則這些系統的執行將沒有分支資訊。 |
