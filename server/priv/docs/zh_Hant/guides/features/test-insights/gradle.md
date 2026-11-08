---
{
  "title": "Gradle 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Gradle 測試分析數據，以監控測試效能。"
}
---
# Gradle 測試洞察 {#gradle-test-insights}

> [!IMPORTANT]
> **必要條件**
>
> - 已套用 `dev.tuist` Gradle 外掛程式，詳情請參閱 <.localized_link href="/guides/get-started/gradle-project">從 Gradle 專案開始</.localized_link>。

Tuist 的 Gradle 外掛程式會在每次測試任務執行後自動上傳測試結果，讓你能在 Tuist 儀表板中直接查看測試效能與不穩定測試。

一旦套用了外掛程式，就會自動收集測試洞察資料。不需要額外設定。

你可以在 Tuist 儀表板中存取測試洞察資料，並觀察其隨時間的變化：

![含測試洞察的儀表板](/images/guides/features/build-insights/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

此外掛程式會收集所有 Gradle `Test` 任務的結果，包括：
- 個別測試案例的通過／失敗狀態與持續時間
- 測試套件與類別結構
- 跨多次執行的不穩定測試偵測

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本機建置的測試結果會在背景中上傳。
- CI 執行的測試結果會在前台上傳，以避免在短暫存活的代理程式上遺失遙測資料。

你可以使用 `uploadInBackground` 中的 `tuist` 區塊來覆寫此行為，位於你的 `settings.gradle.kts` 檔案中：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git 歷史記錄 {#git-history}

在 CI 上，此外掛程式也會在回報測試執行時上傳檢出的提交歷史記錄：提交的 SHA、其父提交、提交日期，以及該次執行與其拉取請求基底分支所在的分支。不會上傳任何檔案內容、提交訊息或作者資訊。這能讓 Tuist 知道哪些提交已合併至你的預設分支，例如合併佇列所測試的提交。此外掛程式會讀取检出已有的歷史記錄；若检出沒有基底分支，則會向遠端查詢其最新提交（`git ls-remote`）。它不會抓取歷史記錄。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取检出內容，不會聯絡遠端。 |
