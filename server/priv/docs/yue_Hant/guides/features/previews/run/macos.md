---
{
  "title": "使用 macOS App 執行預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "使用 Tuist macOS 選單列 App，在裝置和模擬器上執行相容的 Apple 預覽。"
}
---
# 使用 macOS 應用程式執行預覽

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

針對 Apple 預覽，Tuist macOS 選單列應用程式可作為 CLI 的替代方案，無論構建來自 Xcode、Bazel 或 Once。發佈流程的簽署和資格要求仍然適用。

## 安裝 {#install}

[下載應用程式](https://tuist.dev/download)或使用 `brew install --cask tuist/tuist/tuist` 進行安裝。

## 執行構建 {#run-a-build}

在選單列應用程式中選擇相容的裝置或模擬器，然後在預覽頁面點擊 **執行**。

macOS 應用程式會先為每個應用程式請求最新的相容預覽。在較舊的伺服器上（這些伺服器會在套用平台篩選器之前選擇不同的應用程式），它會回退到分頁歷史記錄，而不會施加可能隱藏可用構建的截止限制。

有關存取權限和組織方式，請參閱 <.localized_link href="/guides/features/previews#visibility">可見性和軌道</.localized_link>。
