---
{
  "title": "Debugging",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Use coding agents and local runs to debug issues in Tuist."
}
---
# 除錯{#debugging}

開放性具有實用優勢：程式碼公開可供查閱，您可在地端執行程式，並能運用程式設計代理程式加速解答疑問，同時在程式碼庫中偵測潛在錯誤。

若在除錯時發現文件遺漏或不完整，請更新英文文件（路徑：`docs/` ），並開啟 PR。

## 使用編碼代理{#use-coding-agents}

程式設計代理程式適用於：

- 掃描程式碼庫以定位行為的實作位置。
- 在地端重現問題並快速迭代。
- 追蹤輸入如何流經 Tuist 以找出根本原因。

請提供最簡化的重現案例，並將問題指向特定元件（CLI、伺服器、快取、文件或手冊）。範圍越聚焦，除錯過程將越快速且精準。

### 常需提示語 (FNP){#frequently-needed-prompts}

#### 意外的專案生成{#unexpected-project-generation}

專案生成結果出現預期外狀況。請執行 Tuist CLI 對照我的專案：`/path/to/project`
以釐清問題成因。追蹤生成器管道並指出導致此輸出的程式碼路徑。

#### 生成專案中的可重現錯誤{#reproducible-bug-in-generated-projects}

此問題疑似為生成專案的錯誤。請參照現有範例，於`examples/ 目錄下建立可重現的專案（` ）。新增一個會失敗的驗收測試，透過`xcodebuild`
執行（僅選取該測試），修正問題後重新執行測試確認通過，最後開啟 PR。
