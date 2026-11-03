---
{
  "title": "使用 macOS App 執行預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "使用 Tuist macOS 選單列應用程式，在裝置與模擬器上執行相容的 Apple 預覽。"
}
---
# 用 macOS app 執行預覽

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

對於 Apple 預覽，Tuist macOS 選單列 app 是 CLI 的替代方案，無論建置來自 Xcode、Bazel 或 Once。發布工作流程的簽署與資格要求仍然適用。

## 安裝 {#install}

[下載 app](https://tuist.dev/download)，或使用 `brew install --cask tuist/tuist/tuist` 安裝。

## 執行建置 {#run-a-build}

在選單列 app 中選擇相容的裝置或模擬器，然後在預覽頁面點擊 **執行**。

macOS app 會先為每個 app 請求最新的相容預覽。在較舊的伺服器上（這些伺服器會在套用平台篩選器之前先挑選不同的 app），它會退回使用分頁歷史記錄，而不會施加可能隱藏可用建置的截斷條件。

關於存取權限與組織方式，請參閱 <.localized_link href="/guides/features/previews#visibility">可見度與追蹤</.localized_link>。
