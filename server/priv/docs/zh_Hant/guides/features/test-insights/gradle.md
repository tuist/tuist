---
{
  "title": "Gradle 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Gradle 測試分析資料，以監控測試效能。"
}
---
# Gradle 測試洞察 {#gradle-test-insights}

> [!IMPORTANT]
> **必要條件**
>
> - 已套用 `dev.tuist` Gradle 外掛程式，如 <.localized_link href="/guides/get-started/gradle-project">開始使用 Gradle 專案</.localized_link> 中所述。

Tuist 的 Gradle 外掛程式會在每次執行測試工作後自動上傳測試結果，讓你能直接在 Tuist 儀表板中檢視測試效能與不穩定測試。

一旦套用外掛程式，就會自動收集測試洞察資料。無需額外設定。

你可以在 Tuist 儀表板中存取測試洞察資料，並觀察其隨時間的變化：

![包含測試洞察的儀表板](/images/guides/features/build-insights/tests-dashboard.png)

## 追蹤項目 {#what-is-tracked}

此外掛程式會收集所有 Gradle `Test` 工作的結果，包括：
- 個別測試案例的通過／失敗狀態與持續時間
- 測試套件與類別結構
- 跨多次執行的不穩定測試偵測

啟用 <.localized_link href="/guides/features/test-code-coverage/gradle">程式碼涵蓋率</.localized_link> 以同時上傳測試所執行的程式碼。

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本機建置的測試結果會在背景上傳。
- CI 執行的測試結果會在前台上傳，以避免在短暫存在的代理程式上遺失遙測資料。

你可以使用 `settings.gradle.kts` 中 `tuist` 區塊內的 `uploadInBackground` 來覆寫此行為：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git 歷史記錄 {#git-history}

在 CI 上，此外掛程式在回報測試執行時也會上傳檢出的提交歷史記錄：提交 SHA、其父提交、提交日期，以及該執行與其拉取請求基礎分支所在的分支。不會上傳檔案內容、提交訊息或作者。這能讓 Tuist 知道哪些提交已合併至你的預設分支，例如合併佇列所測試的提交。此外掛程式會讀取检出已有的歷史記錄；若检出沒有基礎分支，則會向遠端查詢其最新提交（`git ls-remote`）。它不會擷取歷史記錄。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取检出，不會聯絡遠端。 |
