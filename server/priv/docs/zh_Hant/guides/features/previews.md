---
{
  "title": "預覽",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Previews 分享行動應用程式、桌面應用程式與命令列工具，讓團隊成員無需在本機重新建置即可試用版本。"
}
---
# 預覽 {#previews}

Tuist Previews 讓團隊成員無需在本機重新建置，即可試用行動應用程式、桌面應用程式和命令列工具。將建置發布至你的 Tuist 專案，然後分享其預覽連結。

## 可預覽的內容 {#what-you-can-preview}

- **行動應用程式：** Android APK 與 Apple 應用程式套件或 IPA。支援的裝置、模擬器與簽署需求取決於發布流程。
- **桌面應用程式：** macOS 應用程式套件。
- **命令列工具：** macOS 或 Linux 可執行檔，可單獨提供或與其相依性一起打包。

請參閱<.localized_link href="/guides/features/previews/types">支援的類型</.localized_link>以了解打包與相容性需求。構件類型決定預覽可在何處執行；它並不規定由哪個建置系統產生。

## 發布預覽 {#publish-a-preview}

選擇你的建置系統以進行設定與發布指令：

<.home_cards>
  <.home_card
    title="Xcode"
    details="分享來自現有 Xcode 專案或 Tuist 生成專案的應用程式。"
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="分享來自 Gradle 專案的 Android 應用程式與原生命令列工具。"
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="透過配套的 Bazel 規則，分享 Android 應用程式、Apple 應用程式與命令列工具。"
    link="/guides/features/previews/bazel"
  />
  <.home_card
    title="Once"
    details="使用 Once 的原生構件提供者，發布符合條件的 Android、Apple 模擬器與 macOS 應用程式。"
    link="/guides/features/previews/once"
  />
</.home_cards>

若你已有受支援的建置，可使用<.localized_link href="/cli/share">`tuist share`</.localized_link>在不含建置系統整合的情況下發布。打包與簽署需求仍然適用。

## 執行預覽 {#run-a-preview}

接收者不需要產生該預覽的建置系統。選擇存取相容建置的方式：

<.home_cards>
  <.home_card
    title="CLI"
    details="使用 tuist run 執行行動應用程式、macOS 應用程式與命令列預覽。"
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="macOS 應用程式"
    details="透過 Tuist 選單列應用程式執行相容的 Apple 預覽。"
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="iPhone 應用程式"
    details="在 iPhone 上尋找並存取你的 Apple 預覽。"
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## 可見性 {#visibility}

預覽使用專案的預設可見性。私人預覽需要驗證與專案存取權限。僅在建置可與任何人分享時，才在專案設定中將預覽設為公開。公開可見性不會繞過平台簽署或裝置安裝需求。

## 軌道 {#tracks}

軌道將預覽整理為具名群組，例如內部測試人員使用的`beta`，或自動化建置使用的`nightly`。在你的工作流程中，透過發布指令指定軌道；軌道會在首次使用時延遲建立。使用它們按用途分組預覽，並在 Tuist 儀表板中篩選預覽。

## README 徽章 {#readme-badge}

在你的儲存庫的`README`中加入指向最新預覽的徽章：

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

將帳號與專案代換為你自己的：

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

若專案包含多個具有不同 bundle identifier 的應用程式，請加入`bundle-id`查詢參數以選擇應用程式：

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
