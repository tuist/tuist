---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# 目錄{#directories}

Tuist 遵循 [XDG
基本目錄規格](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)，在系統上的多個目錄中組織檔案。這提供了一種簡潔、標準的方式來管理組態、快取和狀態檔案。

## 支援的環境變數{#supported-environment-variables}

Tuist 支援標準 XDG 變數和 Tuist 特有的前綴變數。Tuist 特有的變數 (前綴為`TUIST_`)具有優先權，讓您可以將 Tuist
與其他應用程式分開設定。

### 設定目錄{#configuration-directory}

**環境變數：**
- `TUIST_XDG_CONFIG_HOME` (優先)
- `xdg_config_home`

**預設：** `~/.config/tuist`

**用於：**
- 伺服器憑證 (`credentials/{host}.json`)

**範例：**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### 快取記憶體目錄{#cache-directory}

**環境變數：**
- `TUIST_XDG_CACHE_HOME` (優先)
- `XDG_CACHE_HOME`

**預設：** `~/.cache/tuist`

**用於：**
- **外掛程式** ：下載並編譯的外掛程式快取
- **ProjectDescriptionHelpers** ：已編譯的專案描述輔助工具
- **Manifests** ：快取清單檔案
- **專案** ：產生自動化專案快取
- **EditProjects** ：編輯指令的快取記憶體
- **運行**: 測試和建立運行分析資料
- **二進位檔案** ：建立工件二進位檔案 (不可跨環境共享)
- **SelectiveTests** ：選擇性測試快取

**範例：**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### 國家目錄{#state-directory}

**環境變數：**
- `TUIST_XDG_STATE_HOME` (優先)
- `XDG_STATE_HOME`

**預設：** `~/.local/state/tuist`

**用於：**
- **日誌** ：日誌檔案 (`logs/{uuid}.log`)
- **鎖** ：驗證鎖檔案 (`{handle}.sock`)

**範例：**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## 優先順序{#precedence-order}

在決定使用哪個目錄時，Tuist 會依下列順序檢查環境變數：

1. **Tuist 特有的變數** (例如：`TUIST_XDG_CONFIG_HOME`)
2. **標準 XDG 變數** (例如`XDG_CONFIG_HOME`)
3. **預設位置** (例如`~/.config/tuist`)

這可讓您
- 使用標準的 XDG 變數，以一致的方式組織您所有的應用程式
- 當您需要 Tuist 的不同位置時，使用 Tuist 專用變數覆寫
- 依靠合理的預設值，無需任何設定

## 常見用例{#common-use-cases}

### 每個專案隔離 Tuist{#isolating-tuist-per-project}

您可能想要隔離 Tuist 的快取和每個專案的狀態：

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD 環境{#ci-cd-environments}

在 CI 環境中，您可能想要使用臨時目錄：

```yaml
# GitHub Actions example
env:
  TUIST_XDG_CACHE_HOME: /tmp/tuist-cache
  TUIST_XDG_STATE_HOME: /tmp/tuist-state

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: tuist generate
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist-state/logs/*.log
```

### 使用獨立目錄進行除錯{#debugging-with-isolated-directories}

在調試問題時，您可能會想要一筆勾消：

```bash
# Create temporary directories for debugging
export TUIST_XDG_CACHE_HOME=$(mktemp -d)
export TUIST_XDG_STATE_HOME=$(mktemp -d)
export TUIST_XDG_CONFIG_HOME=$(mktemp -d)

# Run Tuist commands
tuist generate

# Clean up when done
rm -rf $TUIST_XDG_CACHE_HOME $TUIST_XDG_STATE_HOME $TUIST_XDG_CONFIG_HOME
```
