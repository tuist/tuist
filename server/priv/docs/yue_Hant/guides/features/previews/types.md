---
{
  "title": "支援的預覽類型",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "流動應用程式、macOS 應用程式及命令列預覽的封裝與相容性要求。"
}
---
# 支援的預覽類型

預覽類型決定你打包的內容及其可運行環境，與產生它的構建系統無關。每個發布工作流程都有其自身的簽名和資格要求。

## 移動應用程式 {#mobile-apps}

- **Android：** 已簽署的應用程式 APK。接收者需要相容的 Android 裝置或模擬器。Android App Bundles（`.aab`）並非預覽安裝套件。
- **Apple：** 用於模擬器的應用程式套件，或用於實體裝置的已匯出 IPA。裝置構建需要一個允許在接收者裝置上安裝的描述檔。

<.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>、<.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link> 和 <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link> 指南說明了每個工作流程可以發布哪些輸出。例如，Bazel 和 Once 發布支援符合資格的 Apple 模擬器和 macOS 應用程式，但不支援實體裝置構建。

## 桌面應用程式 {#desktop-apps}

分享已構建的 macOS 應用程式套件：

```bash
tuist share path/to/MyApp.app
```

簽名和公證要求仍然適用。桌面應用程式套件不同於 Tuist macOS 應用程式，後者可供接收者用來運行預覽。

## 命令列工具 {#command-line-tools}

在 macOS 或 Linux 上分享獨立可執行檔：

```bash
tuist share path/to/my-tool
```

如果 CLI 需要資源套件、動態程式庫或輔助可執行檔，請組裝一個分發目錄，並相對於該目錄指定其入口點：

```bash
tuist share path/to/distribution --executable bin/my-tool
```

整個分發目錄都會被上傳。包含你的工具所需的程式庫、資源和輔助檔案，並確保它可以在構建目錄之外運行。腳本需要在接收者的系統上安裝 shebang 和解譯器。

可執行檔本身不帶圖示。透過 `--icon` 傳遞 PNG 以在預覽中顯示圖示，例如用於 Linux 桌面應用程式：

```bash
tuist share path/to/distribution --executable bin/my-app --icon path/to/icon.png
```

## 多個 CLI 目標 {#multiple-cli-targets}

預覽將同一個 CLI 針對單一提交的構建分組；每個構建包含一個作業系統和一種或多種 CPU 架構的分發。例如，一個預覽可以包含 macOS arm64、macOS x86_64 和 Linux x86_64 分發。通用 macOS 可執行檔在一次構建中涵蓋兩種 Mac 架構。

分別構建每個目標，然後從相同的 Git 檢出使用相同的入口點基本名稱和追蹤 sequentially 發布分發：

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

這些上傳會將構建添加到同一個預覽連結。在所有上傳中保持專案、提交、發布帳戶、CLI 名稱和追蹤一致。Tuist 會選擇與接收者作業系統和 CPU 架構相符的構建。

## 客戶端與伺服器相容性 {#client-and-server-compatibility}

使用最新版本的 Tuist CLI 來運行桌面和命令列預覽。如果你自行託管 Tuist，請在發布這些類型之前更新你的伺服器。移動預覽仍可與較舊的客戶端配合使用。

為接收者的作業系統和 CPU 架構進行構建。Tuist 不會交叉編譯你的應用程式或安裝其依賴項；Linux 工具也需要相容的系統程式庫。

預覽以你的使用者帳戶權限運行，而非在沙箱中。僅運行你信任的作者和拉取請求的構建。

參閱 <.localized_link href="/guides/features/previews/run/cli">使用 CLI 運行預覽</.localized_link> 了解執行行為和參數轉發，以及 <.localized_link href="/guides/features/previews#visibility">預覽概覽</.localized_link> 了解存取權限、追蹤和 README 徽章。
