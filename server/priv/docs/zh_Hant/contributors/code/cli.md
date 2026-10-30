---
{
  "title": "CLI",
  "titleTemplate": ":title · 程式碼 · 貢獻者 · Tuist",
  "description": "為 Tuist CLI 做出貢獻。"
}
---
# CLI {#cli}

來源：[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist) 與 [github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## 用途 {#what-it-is-for}

CLI 是 Tuist 的核心。它負責專案生成、自動化工作流程（測試、執行、圖表與檢查），並提供與 Tuist 伺服器的介面，以支援驗證、快取、洞察、預覽、Registry 與選擇性測試等功能。

## 如何貢獻 {#how-to-contribute}

### 需求 {#requirements}

- macOS 14.0+
- Xcode 26+

### 本機設定 {#set-up-locally}

- 複製儲存庫：`git clone git@github.com:tuist/tuist.git`
- 使用 [官方安裝腳本](https://mise.jdx.dev/getting-started.html)（而非 Homebrew）安裝 Mise，並執行 `mise install`
- 安裝 Tuist 相依套件：`tuist install`
- 生成工作區：`tuist generate`

生成的專案會自動開啟。若之後需要重新開啟，請執行 `open Tuist.xcworkspace`。

> [!NOTE]
> **Xed .**
>
> 若嘗試使用 `xed .` 開啟專案，將會開啟套件而非 Tuist 生成的工作區。請使用 `Tuist.xcworkspace`。


### 執行 Tuist {#run-tuist}

#### 從 Xcode {#from-xcode}

編輯 `tuist` Scheme 並設定參數，例如 `generate --no-open`。將工作目錄設為專案根目錄（或使用 `--path`）。

> [!WARNING]
> **Projectdescription 編譯**
>
> CLI 依賴 `ProjectDescription` 的建置。若執行失敗，請先建置 `Tuist-Workspace` Scheme。


#### 從終端機 {#from-the-terminal}

首先生成工作區：

```bash
tuist generate --no-open
```

接著使用 Xcode 建置 `tuist` 執行檔，並從 DerivedData 執行：

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

或透過 Swift Package Manager：

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
