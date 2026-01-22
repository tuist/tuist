---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# 問題回報{#issue-reporting}

身為 Tuist 使用者，您可能會遇到錯誤或異常行為。若發生此類情況，我們鼓勵您提交回報，以便我們進行修復。

## GitHub Issues 是我們的工單平台{#github-issues-is-our-ticketing-platform}

問題應透過 GitHub 提交為 [GitHub issues](https://github.com/tuist/tuist/issues)，而非透過
Slack 或其他平台。GitHub
更利於追蹤與管理問題，與程式碼庫更緊密連結，並能協助我們監控問題進度。此外，此舉可鼓勵提交者以長篇描述闡述問題，迫使報告者深入思考問題本質並提供更完整背景資訊。

## 上下文至關重要{#context-is-crucial}

若問題描述缺乏足夠背景資訊，將被視為不完整並要求作者補充說明。若未提供補充，該問題將被關閉。請理解：您提供的背景資訊越詳盡，我們就越容易理解問題並進行修復。因此若希望問題獲得解決，請盡可能提供完整背景。請嘗試回答以下問題：

- 你原本想做什麼？
- 你的圖表看起來如何？
- 您正在使用哪個版本的 Tuist？
- 這是否阻礙了您？

我們同時要求您提供可重現的最小**專案：** 。

## 可重現專案{#reproducible-project}

### 何謂可重現專案？{#what-is-a-reproducible-project}

可重現專案是小型 Tuist 專案，用以示範問題——此類問題通常源於 Tuist 中的錯誤。您的可重現專案應僅包含清晰示範該錯誤所需的最低限度功能。

### 為何需要建立可重現的測試案例？{#why-should-you-create-a-reproducible-test-case}

可重現的專案能讓我們隔離問題根源，這是解決問題的第一步！任何錯誤報告中最關鍵的部分，就是描述精確的錯誤重現步驟。

可重現專案是分享特定錯誤環境的絕佳方式。您的可重現專案正是協助他人協助您的最佳途徑。

### 建立可重現專案的步驟{#steps-to-create-a-reproducible-project}

- 建立新的 git 儲存庫。
- 在儲存庫目錄中執行 ``` 啟動專案：`tuist init` `
- 請添加重現您所見錯誤所需的程式碼。
- 發布程式碼（您的 GitHub 帳戶是理想發布平台），並在建立問題時提供連結。

### 可重現專案的優勢{#benefits-of-reproducible-projects}

- **更小的表面積：** 透過移除除錯誤外的所有內容，您無需費力挖掘即可找到問題所在。
- **無需公開機密程式碼：** 您可能因各種原因無法公開主網站。將其中一小部分重製為可重現的測試案例，即可在不洩露任何機密程式碼的前提下，公開展示問題所在。
- **錯誤證明：**
  有時錯誤源於您機器上某些設定的組合。可重現的測試案例能讓貢獻者下載您的建置版本，並在他們的機器上進行測試。這有助於驗證並縮小問題的成因範圍。
- **獲取錯誤修復協助：** 若他人能重現您的問題，通常更有機會解決該問題。若無法重現錯誤，幾乎不可能進行修復。
