---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# 發佈

Tuist採用持續發布系統，每當有實質變更合併至主分支時，便會自動發佈新版本。此機制確保改進能迅速觸及使用者，無需維護者人工介入。

## 概述

我們持續發布三大核心組件：
- **Tuist CLI** - 命令列工具
- **Tuist Server** - 後端服務
- **Tuist App** - macOS 與 iOS 應用程式（iOS 應用程式僅持續部署至
  TestFlight，詳情請參閱[此處](#app-store-release)）

每個元件皆擁有獨立的發布管道，每當向主分支推送程式碼時，該管道便會自動執行。

## 運作原理

### 1. 提交規範

我們採用[標準化提交規範](https://www.conventionalcommits.org/)來結構化提交訊息。此規範使工具能理解變更性質、判定版本遞增，並生成相應的變更日誌。

格式：`類型(範圍)：描述`

#### 提交類型及其影響

| 輸入      | 說明        | 版本影響           | 範例                          |
| ------- | --------- | -------------- | --------------------------- |
| `feat`  | 新功能或能力    | 次要版本更新 (x.Y.z) | `feat(cli)：新增 Swift 6 支援功能` |
| `修正`    | 錯誤修正      | 版本號更新（x.y.Z）   | `修復(app)：解決開啟專案時發生當機的問題`    |
| `文件`    | 文件變更      | 無釋出            | `文件：更新安裝指南`                 |
| `樣式`    | 程式碼樣式變更   | 無釋出            | `樣式：使用 swiftformat 格式化程式碼`  |
| `重構`    | 程式碼重構     | 無釋出            | `重構(伺服器端)：簡化驗證邏輯`           |
| `perf`  | 效能提升      | 版本號更新          | `perf(cli)：優化依賴解析`          |
| `測試`    | 測試新增/修改內容 | 無釋出            | `測試：為快取新增單元測試`              |
| `chore` | 維護任務      | 無釋出            | `待辦事項：更新依賴項`                |
| `ci`    | CI/CD 變更  | 無釋出            | `ci: 新增版本發佈工作流程`            |

#### 重大變更

重大變更將觸發版本號大幅提升（X.0.0），並應於提交說明中註明：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 變更偵測

各元件使用 [git cliff](https://git-cliff.org/) 來：
- 分析自上次發布以來的提交記錄
- 依範圍篩選提交（命令列介面、應用程式、伺服器）
- 判斷是否存在可釋出的變更
- 自動生成變更記錄

### 3. 發布流程

當偵測到可發布的變更時：

1. **版本計算**: 管道系統將自動判定下一版本編號
2. **變更日誌生成**: git cliff 根據提交訊息生成變更日誌
3. **建置流程**: 此元件已完成建置與測試
4. **發佈建立**: 建立包含建置成果的 GitHub 發佈
5. **發行管道**: 更新將推送至套件管理器（例如 CLI 的 Homebrew）

### 4. 範圍篩選

各元件僅在發生相關變更時才發布：

- **CLI**: 使用`(cli)提交` scope或無scope
- **App**: 提交內容包含`(app)` 範圍
- **伺服器**: 提交記錄`(伺服器)` 範圍

## 撰寫優質的提交訊息

由於提交訊息會直接影響發行說明，撰寫清晰且具描述性的訊息至關重要：

### 應做：
- 使用現在式：譯作「新增功能」而非「新增的功能」
- 簡潔但具描述性
- 若變更僅涉及特定元件，請標明範圍
- 相關參考問題：`fix(cli): 解決建置快取問題 (#1234)`

### 請勿：
- 使用模糊訊息如「修復錯誤」或「更新程式碼」
- 將多個無關的修改合併至單一提交
- 遺漏重大變更資訊

### 重大變更

若涉及重大變更，請在提交說明中加入`重大變更：` ：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 發佈工作流程

發佈工作流程定義於：
- `.github/workflows/cli-release.yml` - CLI 發行版本
- `.github/workflows/app-release.yml` - App releases
- `.github/workflows/server-release.yml` - 伺服器發佈

每個工作流程：
- 於主分支推送時執行
- 可手動觸發
- 使用 git cliff 進行變更檢測
- 負責整個發佈流程

## 監控發佈

您可透過以下管道監控發布動態：
- [GitHub Releases 頁面](https://github.com/tuist/tuist/releases)
- GitHub Actions 工作流程執行分頁
- 各元件目錄內的變更記錄檔

## 效益

此持續發布模式提供：

- **快速交付**: 合併後變更立即推送至用戶端
- **減少瓶頸**: 無需等待人工釋出
- **清晰溝通**: 自動生成提交訊息的變更記錄
- **一致流程**: 所有元件採用相同發布流程
- **品質保證**: 僅發布經測試的變更

## 疑難排解

若發布失敗：

1. 檢查 GitHub Actions 日誌以確認失敗的工作流程
2. 請確保您的提交訊息遵循慣用格式
3. 確認所有測試皆通過
4. 檢查元件是否成功建置

針對需立即發布的緊急修正：
1. 確保您的提交具有明確的範圍
2. 合併後，請監控發布工作流程
3. 如有需要，請觸發手動發布

## App Store 發行

雖然命令列介面（CLI）與伺服器遵循上述持續發布流程，但由於蘋果App Store審核機制，**的iOS應用程式** 屬例外情況：

- **手動發布**: iOS 應用程式發布需手動提交至 App Store
- **審核延遲**: 每次發布都必須經過 Apple 的審核流程，此流程可能需要 1-7 天
- **批次變更**: 每次 iOS 發行通常會將多項變更打包處理
- **TestFlight**: 測試版可能透過 TestFlight 發布，早於 App Store 上架
- **版本說明**: 必須專為 App Store 指南撰寫

iOS 應用程式仍遵循相同的提交規範，並使用 git cliff 生成變更日誌，但實際發布給用戶的頻率較低，且採手動排程。
