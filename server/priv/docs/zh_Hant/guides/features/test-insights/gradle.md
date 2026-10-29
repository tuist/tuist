---
{
  "title": "Gradle Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Gradle test analytics in the Tuist dashboard to monitor test performance."
}
---
# Gradle 測試洞察 {#gradle-test-insights}

Tuist 的 Gradle 外掛程式會在每次測試任務執行後自動上傳測試結果，讓你能夠直接在 Tuist 儀表板中查看測試效能和不穩定測試。

當套用 Tuist Gradle 外掛程式時，系統會自動收集測試洞察資料——除了初始外掛程式設定外，無需額外設定。

你可以在 Tuist 儀表板中存取測試洞察資料，並查看其隨時間的變化：

![包含測試洞察的儀表板](/images/guides/features/build-insights/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

此外掛程式會收集所有 Gradle `Test` 任務的結果，包括：
- 個別測試案例的通過/失敗狀態與持續時間
- 測試套件與類別結構
- 跨多次執行的不穩定測試偵測

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本機建構的測試結果會在背景上傳。
- CI 執行的測試結果會在前台上傳，以避免在短暫存在的代理程式上遺失遙測資料。

你可以使用 `uploadInBackground` 中的 `tuist` 區塊來覆寫此行為，該區塊位於你的 `settings.gradle.kts` 中：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git 歷史記錄 {#git-history}

在 CI 上，此外掛程式在報告測試執行時也會上傳檢出版本的提交歷史記錄：提交 SHA、其父提交、提交日期，以及該執行及其拉取請求基礎分支所在的分支。不會上傳檔案內容、提交訊息或作者資訊。這能讓 Tuist 知道哪些提交已合併至你的預設分支，例如合併佇列所測試的提交。此外掛程式會讀取檢出版本已有的歷史記錄，若檢出版本沒有基礎分支，則會向遠端查詢其最新提交（`git ls-remote`）。它不會抓取歷史記錄。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取檢出版本，不會聯絡遠端。 |
