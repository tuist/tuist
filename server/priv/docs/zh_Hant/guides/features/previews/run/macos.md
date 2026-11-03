---
{
  "title": "使用 macOS 應用程式執行預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "使用 Tuist macOS 選單列應用程式，在裝置與模擬器上執行相容的 Apple 預覽。"
}
---
# 使用 macOS 應用程式執行預覽

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

針對 Apple 預覽，Tuist macOS 選單列應用程式是 CLI 的替代方案，無論建置來自 Xcode、Bazel 或 Once。發布流程的簽署與資格要求仍然適用。

## 安裝 {#install}

[下載應用程式](https://tuist.dev/download)，或使用 `brew install --cask tuist/tuist/tuist` 進行安裝。

## 執行建置 {#run-a-build}

在選單列應用程式中選擇相容的裝置或模擬器，然後在預覽頁面點擊 **執行**。

macOS 應用程式會先為每個應用程式請求最新的相容預覽。在套用平台篩選條件前先挑選不同應用程式的舊版伺服器上，它會退回至分頁歷史記錄，且不會設定可能隱藏可用建置的截止點。

關於存取權限與組織方式，請參閱 <.localized_link href="/guides/features/previews#visibility">可見度與追蹤</.localized_link>。
