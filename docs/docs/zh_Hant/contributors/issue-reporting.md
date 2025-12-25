---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# 問題報告{#issue-reporting}

身為 Tuist 的使用者，您可能會遇到 bug 或意想不到的行為。如果您遇到了，我們鼓勵您報告這些問題，以便我們進行修復。

## GitHub issues 是我們的票單平台{#github-issues-is-our-ticketing-platform}

問題應該在 GitHub 上以 [GitHub issues](https://github.com/tuist/tuist/issues)
的方式報告，而不是在 Slack 或其他平台上。GitHub
更適合追蹤和管理問題，也更接近程式碼庫，讓我們可以追蹤問題的進度。此外，它鼓勵對問題進行長篇描述，迫使報告者思考問題，並提供更多上下文。

## 背景是關鍵{#context-is-crucial}

沒有足夠上下文的問題將被視為不完整，作者將被要求提供額外的上下文。如果沒有提供，問題將被關閉。這樣想：您提供的上下文越多，我們就越容易了解問題並修復它。因此，如果您希望問題獲得修復，請儘可能提供更多內容。嘗試回答下列問題：

- 你想做什麼？
- 您的圖表看起來如何？
- 您使用的是什麼版本的 Tuist？
- 這會阻礙您嗎？

我們也要求您提供最少**可重複的專案** 。

## 可重複的專案{#reproducible-project}

### 什麼是可重複專案？{#what-is-a-reproducible-project}

可重複專案是一個小型的 Tuist 專案，用來展示一個問題 - 通常這個問題是由 Tuist 中的 bug
所引起的。您的可重現專案應包含清楚展示錯誤所需的最基本功能。

### 為什麼要建立可重複的測試案例？{#why-should-you-create-a-reproducible-test-case}

可重複的專案可讓我們隔離問題的起因，這是修正問題的第一步！任何錯誤報告最重要的部分是描述重現錯誤所需的確切步驟。

可重複專案是分享造成錯誤的特定環境的好方法。您的可重複專案是幫助想要幫助您的人的最佳方式。

### 建立可重複專案的步驟{#steps-to-create-a-reproducible-project}

- 建立新的 git 倉庫。
- 使用`tuist init` 在儲存庫目錄中初始化專案。
- 新增重新產生您所看到的錯誤所需的程式碼。
- 發佈程式碼（您的 GitHub 帳戶是個很好的地方），然後在建立問題時連結到它。

### 可重複專案的優點{#benefits-of-reproducible-projects}

- **較小的表面面積：** 透過移除除錯誤以外的所有東西，您就不必挖地三尺也要找出錯誤。
- **無需發佈秘密碼：** 您可能無法發佈您的主網站 (有許多原因)。將其中一小部分重新製作為可重複的測試案例，可讓您公開展示問題，而無需揭露任何秘密程式碼。
- **錯誤的證明：**
  有時候，錯誤是由您電腦上的某些組合設定所造成的。可重複的測試案例可讓貢獻者下載您的建立檔，並在他們的機器上進行測試。這有助於驗證並縮小產生問題的原因。
- **尋求協助修復您的錯誤：** 如果其他人能夠重現您的問題，他們通常就有很大的機會修復問題。如果不先重現問題，幾乎不可能修復錯誤。
