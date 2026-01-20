---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# 新聞稿

Tuist 使用持續發佈系統，每當有意義的變更合併到主分支時，系統就會自動發佈新版本。此方法可確保所做的改進能快速傳達給使用者，而無需維護人員的手動介入。

## 概述

我們持續發佈三個主要元件：
- **Tuist CLI** - 指令列工具
- **Tuist 伺服器** - 後端服務
- **Tuist 應用程式** - macOS 和 iOS 應用程式 (iOS 應用程式僅持續部署至 TestFlight，請參閱
  [此處](#app-store-release))

每個元件都有自己的發行管道，每次推送到主分支時都會自動執行。

## 如何運作

### 1.承諾慣例

我們使用 [Conventional Commits](https://www.conventionalcommits.org/)
來結構我們的提交訊息。這可讓我們的工具了解變更的性質、決定版本的升級，並產生適當的變更記錄。

格式：`種類(範圍)：描述`

#### 承諾類型及其影響

| 類型    | 說明       | 版本影響             | 範例                         |
| ----- | -------- | ---------------- | -------------------------- |
| `功勋`  | 新功能或能力   | 次要版本提升 (x.Y.z)   | `feat(cli): 新增 Swift 6 支援` |
| `定`   | 錯誤修正     | 修補程式版本提升 (x.y.Z) | `fix(app): 解決開啟專案時當機的問題`   |
| `文件`  | 文件變更     | 無發佈              | `說明文件：更新安裝指南`              |
| `風格`  | 程式碼樣式變更  | 無發佈              | `樣式：使用 swiftformat 格式化程式碼` |
| `重構`  | 程式碼重整    | 無發佈              | `重構(server)：簡化認證邏輯`        |
| `敷衍`  | 效能改善     | 補丁版本提升           | `perf(cli): 最佳化依賴解析`       |
| `測試`  | 測試新增/變更  | 無發佈              | `test: 新增快取的單元測試`          |
| `苦差事` | 維護任務     | 無發佈              | `苦差事：更新相依性`                |
| `ci`  | CI/CD 變更 | 無發佈              | `CI：新增發行版本的工作流程`           |

#### 突破性變更

破壞性變更會觸發主要版本提升 (X.0.0)，並應在提交正文中註明：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2.變更偵測

每個元件使用 [git cliff](https://git-cliff.org/) 來：
- 分析自上次發行後的提交
- 依範圍 (用戶端、應用程式、伺服器) 過濾提交內容
- 確定是否有可釋放的變更
- 自動產生更新記錄

### 3.釋放管線

偵測到可釋放變更時：

1. **版本計算** ：流水線決定下一個版本號
2. **變更日誌產生**: git cliff 可從提交訊息建立變更日誌
3. **建置流程** ：元件已建立並測試
4. **版本建立** ：GitHub 發行版本與工件一起建立
5. **發行** ：更新會推送給套件管理員 (例如：Homebrew for CLI)

### 4.範圍過濾

每個元件只有在有相關變更時才會釋放：

- **CLI**: 提交範圍為`(cli)` 或無範圍
- **應用程式** ：與`(app)` 範圍的提交
- **伺服器** ：與`(伺服器)` 範圍的提交

## 撰寫良好的提交訊息

由於提交訊息會直接影響發行說明，因此撰寫清楚、具說明性的訊息非常重要：

### 做：
- 使用現在式：「增加功能」而非「增加功能」。
- 要簡潔但具描述性
- 當變更為特定元件時，包含範圍
- 適用時請參考問題：`fix(cli)：解決建立快取記憶體的問題 (#1234)`

### 不要
- 使用含糊不清的訊息，例如「修正錯誤」或「更新程式碼」。
- 在一次提交中混合多個不相關的變更
- 忘記包含故障變更資訊

### 突破性變更

如果是破壞性的變更，請在提交正文中包含`BREAKING CHANGE:` ：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 發佈工作流程

發佈工作流程定義在
- `.github/workflows/cli-release.yml` - CLI 發行版本
- `.github/workflows/app-release.yml` - 應用程式版本
- `.github/workflows/server-release.yml` - 伺服器版本

每個工作流程：
- 在推到主機時運行
- 可手動觸發
- 使用 git cliff 檢測變更
- 處理整個發行流程

## 監控釋放

您可以透過以下方式監控釋出：
- [GitHub 發佈頁面](https://github.com/tuist/tuist/releases)。
- 工作流程執行的 GitHub 動作索引標籤
- 各元件目錄中的變更日誌檔案

## 優點

這種持續釋放的方式提供了

- **快速交付** ：合併變更後立即送達使用者
- **減少瓶頸** ：無須等待手動釋放
- **清晰的溝通** ：從提交訊息自動更新更新記錄
- **一致的流程** ：所有元件採用相同的發行流程
- **品質保證** ：僅發佈經過測試的變更

## 疑難排解

如果釋放失敗：

1. 檢查 GitHub Actions 日誌，找出失敗的工作流程
2. 確保您的提交訊息遵循傳統格式
3. 驗證所有測試都通過
4. 檢查元件是否成功建立

用於需要立即釋放的緊急修復：
1. 確保您的委託有明確的範圍
2. 合併後，監控發行工作流程
3. 如果需要，觸發手動釋放

## App Store 發佈

CLI 和 Server 遵循上述的持續釋出程序，而**iOS 應用程式** 則因 Apple 的 App Store 審核程序而例外：

- **手動發佈**: iOS 應用程式發佈需要手動提交至 App Store
- **審核延遲** ：每個版本都必須經過 Apple 的審核程序，可能需要 1-7 天的時間
- **分批變更** ：每個 iOS 版本通常會將多項變更捆綁在一起
- **TestFlight** ：Beta 版本可在 App Store 發佈前透過 TestFlight 發佈
- **發行說明** ：必須特別針對 App Store 指南撰寫

iOS 應用程式仍遵循相同的提交慣例，並使用 git cliff 來產生變更日誌，但實際發放給使用者的頻率較低，並採用手動排程。
