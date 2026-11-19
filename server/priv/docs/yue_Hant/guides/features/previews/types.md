---
{
  "title": "支援的預覽類型",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "流動應用程式、macOS 應用程式及命令列預覽的封裝與相容性要求。"
}
---
# 支援嘅預覽類型

預覽類型決定你打包咩同埋佢喺邊度可以運行，同產生佢嘅構建系統無關。每個發布流程都有自己嘅簽署同資格要求。

## 流動應用程式 {#mobile-apps}

- **Android：** 已簽署嘅應用程式 APK。接收者需要相容嘅 Android 裝置或模擬器。Android App Bundles (`.aab`) 唔係預覽安裝套件。
- **Apple：** 用於模擬器嘅應用程式捆綁包，或者用於實體裝置嘅已匯出 IPA。裝置構建需要一個允許喺接收者裝置上安裝嘅配置描述檔。

<.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>、<.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link> 同 <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link> 指南說明每個工作流程可以發布邊啲輸出。例如，Bazel 同 Once 發布支援符合資格嘅 Apple 模擬器同 macOS 應用程式，而唔係實體裝置構建。

## 桌面應用程式 {#desktop-apps}

分享已構建嘅 macOS 應用程式捆綁包：

```bash
tuist share path/to/MyApp.app
```

簽署同公證要求仍然適用。桌面應用程式捆綁包同 Tuist macOS 應用程式唔同，後者係接收者可以用來運行預覽嘅。

## 命令列工具 {#command-line-tools}

喺 macOS 或 Linux 上分享獨立可執行檔：

```bash
tuist share path/to/my-tool
```

如果 CLI 需要資源捆綁包、動態程式庫或輔助可執行檔，請組裝一個分發目錄並指定相對於該目錄嘅入口點：

```bash
tuist share path/to/distribution --executable bin/my-tool
```

整個分發目錄都會被上傳。包含你嘅工具需要嘅程式庫、資源同輔助程式，並確保佢可以喺你嘅構建目錄之外運行。腳本需要 shebang 同埋喺接收者系統上安裝咗嘅直譯器。

可執行檔本身冇圖示。透過 `--icon` 傳遞 PNG 以喺預覽中顯示圖示，例如用於 Linux 桌面應用程式：

```bash
tuist share path/to/distribution --executable bin/my-app --icon path/to/icon.png
```

## 多個 CLI 目標 {#multiple-cli-targets}

預覽將同一個 CLI 針對單一提交嘅構建分組；每個構建包含針對一個作業系統同一個或多個 CPU 架構嘅分發。例如，一個預覽可以包含 macOS arm64、macOS x86_64 同 Linux x86_64 分發。通用 macOS 可執行檔喺一次構建中涵蓋兩種 Mac 架構。

分別構建每個目標，然後使用相同嘅入口點基本名稱同軌道，從同一個 Git 檢出版本順序發布分發：

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

呢啲上傳會將構建添加到同一個預覽連結。確保項目、提交、發布帳戶、CLI 名稱同軌道喺所有上傳中保持一致。Tuist 會選擇與接收者作業系統同 CPU 架構匹配嘅構建。

## 客戶端同伺服器相容性 {#client-and-server-compatibility}

使用最新嘅 Tuist CLI 來運行桌面同命令列預覽。如果你自行託管 Tuist，請喺發布呢啲類型之前更新你嘅伺服器。流動預覽繼續與較舊嘅客戶端兼容。

為你接收者嘅作業系統同 CPU 架構進行構建。Tuist 唔會交叉編譯你嘅應用程式或安裝其依賴項；Linux 工具亦需要相容嘅系統程式庫。

預覽以你用戶帳戶嘅權限運行，而唔係喺沙盒中。只運行你信任嘅作者同拉取請求嘅構建。

參閱 <.localized_link href="/guides/features/previews/run/cli">使用 CLI 運行預覽</.localized_link> 了解執行行為同參數轉發，以及 <.localized_link href="/guides/features/previews#visibility">預覽概覽</.localized_link> 了解訪問權限、軌道同 README 徽章。
