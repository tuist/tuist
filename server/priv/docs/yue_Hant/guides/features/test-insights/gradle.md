---
{
  "title": "Gradle 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Gradle 測試分析數據，以監控測試效能。"
}
---
# Gradle 測試洞察 {#gradle-test-insights}

Tuist 的 Gradle 外掛會在每次測試任務執行後自動上傳測試結果，讓你能直接在 Tuist 儀表板中查看測試效能和不穩定測試。

當套用 Tuist Gradle 外掛時，系統會自動收集測試洞察——除初始外掛設定外，無需額外配置。

你可以在 Tuist 儀表板中存取測試洞察，並查看其隨時間的變化：

![顯示測試洞察的儀表板](/images/guides/features/build-insights/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

此外掛會收集所有 Gradle `Test` 任務的結果，包括：
- 個別測試案例的通過／失敗狀態及持續時間
- 測試套件與類別結構
- 跨執行偵測不穩定測試

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本機建構的測試結果會在背景上傳。
- CI 執行的測試結果會在前台上傳，以避免在短暫存在的代理程式上遺失遙測數據。

你可以使用 `uploadInBackground` 在 `tuist` 區塊中覆寫此行為（位於你的 `settings.gradle.kts`）：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git 歷史記錄 {#git-history}

在 CI 上，此外掛於回報測試執行時也會上傳檢出版本的提交歷史記錄：提交 SHA、其父提交、提交日期，以及該執行與其拉取請求基礎分支所在的分支。不會上傳檔案內容、提交訊息或作者資訊。這能讓 Tuist 知道哪些提交已合併至你的預設分支，例如合併佇列所測試的提交。此外掛會讀取檢出版本已有的歷史記錄；若檢出版本沒有基礎分支，則會向遠端查詢其最新提交（`git ls-remote`）。它不會抓取歷史記錄。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取檢出版本，不會聯絡遠端。 |
