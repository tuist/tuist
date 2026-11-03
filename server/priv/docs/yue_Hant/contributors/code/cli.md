---
{
  "title": "CLI",
  "titleTemplate": ":title · 程式碼 · 貢獻者 · Tuist",
  "description": "為 Tuist CLI 作出貢獻。"
}
---
# CLI {#cli}

來源：[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist) 同 [github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## 用途 {#what-it-is-for}

CLI 係 Tuist 嘅核心。佢負責項目生成、自動化工作流程（測試、運行、圖表同檢查），並提供連接 Tuist server 嘅介面，支援認證、快取、insights、預覽、registry 同選擇性測試等功能。

## 如何貢獻 {#how-to-contribute}

### 要求 {#requirements}

- macOS 14.0+
- Xcode 26+

### 本地設定 {#set-up-locally}

- 複製儲存庫：`git clone git@github.com:tuist/tuist.git`
- 使用 [官方安裝腳本](https://mise.jdx.dev/getting-started.html) 安裝 Mise（唔好用 Homebrew），然後執行 `mise install`
- 安裝 Tuist 依賴：`tuist install`
- 生成工作區：`tuist generate`

生成嘅項目會自動開啟。如果之後需要重新開啟，請執行 `open Tuist.xcworkspace`。

> [!NOTE]
> **Xed .**
>
> 如果你嘗試用 `xed .` 開啟項目，佢會開啟套件，而唔係 Tuist 生成嘅工作區。請使用 `Tuist.xcworkspace`。


### 運行 Tuist {#run-tuist}

#### 從 Xcode {#from-xcode}

編輯 `tuist` scheme 並設定參數，例如 `generate --no-open`。將工作目錄設為項目根目錄（或使用 `--path`）。

> [!WARNING]
> **Projectdescription 編譯**
>
> CLI 依賴 `ProjectDescription` 被構建。如果運行失敗，請先構建 `Tuist-Workspace` scheme。


#### 從終端機 {#from-the-terminal}

首先生成工作區：

```bash
tuist generate --no-open
```

然後用 Xcode 構建 `tuist` 可執行檔，並從 DerivedData 運行：

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

或透過 Swift Package Manager：

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
