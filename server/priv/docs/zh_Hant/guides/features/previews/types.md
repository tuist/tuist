---
{
  "title": "支援的預覽類型",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "行動應用程式、macOS 應用程式和命令列預覽的封裝與相容性需求。"
}
---
# 支援的預覽類型

預覽類型決定你要封裝的內容以及可在何處執行，與產生它的建置系統無關。每種發布工作流程都有各自的簽署與資格要求。

## 行動應用程式 {#mobile-apps}

- **Android：** 已簽署的應用程式 APK。接收者需要相容的 Android 裝置或模擬器。Android App Bundles（`.aab`）並非預覽安裝套件。
- **Apple：** 用於模擬器的應用程式套件，或用於實體裝置的匯出 IPA。裝置建置需要允許在接收者裝置上安裝的描述檔。

<.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>、<.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link> 與 <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link>指南說明每種工作流程可發布哪些輸出。例如，Bazel 與 Once 發布支援符合資格的 Apple 模擬器與 macOS 應用程式，不支援實體裝置建置。

## 桌面應用程式 {#desktop-apps}

分享已建置的 macOS 應用程式套件：

```bash
tuist share path/to/MyApp.app
```

簽署與公證要求仍然適用。桌面應用程式套件不同於 Tuist macOS 應用程式，後者可讓接收者用來執行預覽。

## 命令列工具 {#command-line-tools}

在 macOS 或 Linux 上分享獨立可執行檔：

```bash
tuist share path/to/my-tool
```

如果 CLI 需要資源套件、動態程式庫或輔助可執行檔，請組裝一個發行目錄，並相對於該目錄指定其進入點：

```bash
tuist share path/to/distribution --executable bin/my-tool
```

整個發行目錄都會被上傳。包含你的工具所需的程式庫、資源與輔助程式，並確保它能在建置目錄之外執行。腳本需要 shebang，且接收者的系統上必須安裝對應的直譯器。

## 多個 CLI 目標 {#multiple-cli-targets}

預覽會將同一個 CLI 針對單一提交的多次建置歸為一組；每次建置包含針對一個作業系統與一種或多種 CPU 架構的發行版。例如，一個預覽可以包含 macOS arm64、macOS x86_64 與 Linux x86_64 發行版。通用 macOS 可執行檔可在一次建置中涵蓋兩種 Mac 架構。

分別建置每個目標，然後從相同的 Git 工作副本依序發布發行版，使用相同的進入點基本名稱與追蹤標籤：

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

這些上傳會將建置加入同一個預覽連結。在各次上傳中保持專案、提交、發布帳號、CLI 名稱與追蹤標籤一致。Tuist 會選擇與接收者作業系統和 CPU 架構相符的建置。

## 用戶端與伺服器相容性 {#client-and-server-compatibility}

使用最新版的 Tuist CLI 來執行桌面與命令列預覽。如果你自行託管 Tuist，請在發布這些類型之前更新伺服器。行動預覽仍可與較舊的用戶端搭配運作。

針對接收者的作業系統與 CPU 架構進行建置。Tuist 不會跨平台編譯你的應用程式或安裝其相依性；Linux 工具也需要相容的系統程式庫。

預覽會以你的使用者帳戶權限執行，而非在沙箱中執行。僅執行你信任的作者與拉取請求所產生的建置。

參閱<.localized_link href="/guides/features/previews/run/cli">使用 CLI 執行預覽</.localized_link>以了解執行行為與參數轉遞，並參閱<.localized_link href="/guides/features/previews#visibility">預覽概覽</.localized_link>以了解存取權限、追蹤標籤與 README 徽章。
