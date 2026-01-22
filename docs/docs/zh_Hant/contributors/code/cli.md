---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI{#cli}

來源：[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist)
與
[github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## 用途說明{#what-it-is-for}

命令列介面（CLI）是 Tuist 的核心。它負責專案生成、自動化工作流程（測試、執行、圖表與檢視），並提供與 Tuist
伺服器的介面，以實現驗證、快取、洞察、預覽、註冊表及選擇性測試等功能。

## 如何貢獻{#how-to-contribute}

### 要求{#requirements}

- macOS 14.0+
- Xcode 26+

### 在本地端設定{#set-up-locally}

- 複製儲存庫：`git clone git@github.com:tuist/tuist.git`
- 請使用[官方安裝腳本](https://mise.jdx.dev/getting-started.html)（非 Homebrew）安裝
  Mise，並執行：`mise install`
- 安裝 Tuist 依賴項：`tuist install`
- 建立工作區：`tuist generate`

生成的專案會自動開啟。若需後續重新開啟，請執行：`開啟 Tuist.xcworkspace`

::: info XED .
<!-- -->
若嘗試使用`xed .` 開啟專案，將開啟套件而非 Tuist 生成的工作區。請使用`Tuist.xcworkspace` 。
<!-- -->
:::

### 執行 Tuist{#run-tuist}

#### 來自 Xcode{#from-xcode}

編輯 ``` 並設定 `` ` 方案，設定參數如 ``` 執行 `generate --no-open` 並將 ``` 設定為工作目錄（或使用
``--path``）。

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
此命令列介面依賴`ProjectDescription` 之建置環境。若執行失敗，請先建置`Tuist-Workspace` 方案。
<!-- -->
:::

#### 從終端機{#from-the-terminal}

首先建立工作區：

```bash
tuist generate --no-open
```

接著使用 Xcode 編譯`tuist` 可執行檔，並從 DerivedData 執行：

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

或透過 Swift Package Manager：

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
