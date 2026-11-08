---
{
  "title": "Previews",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Previews 分享流動應用程式、桌面應用程式及命令列工具，讓團隊成員無需在本機重新建置即可試用版本。"
}
---
# Previews {#previews}

Tuist Previews 讓團隊成員無需在本機重新建置，即可試用流動應用程式、桌面應用程式和命令列工具。將建置發布到你的 Tuist 專案，然後分享其預覽連結。

## 你可以預覽的內容 {#what-you-can-preview}

- **流動應用程式：** Android APK 以及 Apple 應用程式套件或 IPA。支援的裝置、模擬器和簽署要求取決於發布工作流程。
- **桌面應用程式：** macOS 應用程式套件。
- **命令列工具：** macOS 或 Linux 可執行檔，可單獨提供或與其依賴項一併捆綁。

請參閱<.localized_link href="/guides/features/previews/types">支援的類型</.localized_link>以了解封裝和相容性要求。構件類型決定預覽可以在哪裡運行；它並不規定由哪個建置系統產生。

## 發布預覽 {#publish-a-preview}

選擇你的建置系統以進行設定和發布命令：

<.home_cards>
  <.home_card
    title="Xcode"
    details="從現有的 Xcode 專案或 Tuist 產生的專案中分享應用程式。"
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="從 Gradle 專案中分享 Android 應用程式和原生命令列工具。"
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="透過配套的 Bazel 規則分享 Android 應用程式、Apple 應用程式和命令列工具。"
    link="/guides/features/previews/bazel"
  />
  <.home_card
    title="Once"
    details="使用 Once 的原生構件提供者發布符合條件的 Android、Apple 模擬器和 macOS 應用程式。"
    link="/guides/features/previews/once"
  />
</.home_cards>

如果你已有受支援的建置，請使用<.localized_link href="/cli/share">`tuist share`</.localized_link>在沒有建置系統整合的情況下發布它。封裝和簽署要求仍然適用。

## 運行預覽 {#run-a-preview}

接收者不需要產生預覽的建置系統。選擇如何存取相容的建置：

<.home_cards>
  <.home_card
    title="CLI"
    details="使用 tuist run 運行流動應用程式、macOS 應用程式和命令列預覽。"
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="macOS 應用程式"
    details="透過 Tuist 選單列應用程式運行相容的 Apple 預覽。"
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="iPhone 應用程式"
    details="在 iPhone 上尋找並存取你的 Apple 預覽。"
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## 可見性 {#visibility}

預覽使用專案的默認可見性。私人預覽需要身份驗證和專案存取權限。僅在建置可以與任何人分享時，才在專案設定中將預覽設為公開。公開可見性不會繞過平台簽署或裝置安裝要求。

## 追蹤渠道 {#tracks}

追蹤渠道將預覽組織成命名群組，例如`beta`用於內部測試人員，或`nightly`用於自動建置。在你的工作流程中使用發布命令指定追蹤渠道；追蹤渠道會在首次使用時惰性建立。使用它們按目的分組預覽，並在 Tuist 儀表板中過濾預覽。

## README 徽章 {#readme-badge}

在你的儲存庫的`README`中加入指向最新預覽的徽章：

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

將帳戶和專案句柄替換為你自己的：

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

如果專案包含多個具有不同捆綁標識符的應用程式，請加入`bundle-id`查詢參數以選擇應用程式：

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
