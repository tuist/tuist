---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# 目錄{#directories}

Tuist 依循 [XDG
基礎目錄規範](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)，將檔案組織於系統多個目錄中。此架構提供管理設定檔、快取檔與狀態檔的簡潔標準化方式。

## 支援的環境變數{#supported-environment-variables}

Tuist 同時支援標準 XDG 變數與 Tuist 專屬前綴變體。Tuist 專屬變體（前綴為`TUIST_` ）具有優先權，可讓您獨立於其他應用程式設定
Tuist。

### 設定目錄{#configuration-directory}

**環境變數：**
- `TUIST_XDG_CONFIG_HOME` (優先級較高)
- `XDG_CONFIG_HOME`

**預設值：** `~/.config/tuist`

**適用於：**
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

### 快取目錄{#cache-directory}

**環境變數：**
- `TUIST_XDG_CACHE_HOME` (優先級較高)
- `XDG_CACHE_HOME`

**預設值：** `~/.cache/tuist`

**適用於：**
- **外掛程式**: 已下載並編譯的外掛程式快取
- **ProjectDescriptionHelpers**: 編譯專案描述輔助函式
- **清單檔案**: 快取清單檔案
- **專案**: 自動化專案快取生成
- **EditProjects**: 編輯指令快取
- **執行**: 測試與建置執行分析數據
- **二進位檔**: 建立建置產物二進位檔（不可跨環境共享）
- **SelectiveTests**: 選擇性測試快取

**範例：**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### 州目錄{#state-directory}

**環境變數：**
- `TUIST_XDG_STATE_HOME` (優先級較高)
- `XDG_STATE_HOME`

**預設值：** `~/.local/state/tuist`

**適用於：**
- **記錄檔**: 記錄檔 (`logs/{uuid}.log`)
- **鎖定機制**: 驗證鎖定檔案 (`{handle}.sock`)

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

1. **Tuist專屬變數** (例如：`TUIST_XDG_CONFIG_HOME`)
2. **標準 XDG 變數** （例如：`XDG_CONFIG_HOME` ）
3. **預設位置** (例如：`~/.config/tuist`)

這將使您能夠：
- 使用標準 XDG 變數來統一管理所有應用程式
- 若需為 Tuist 設定不同位置，請使用 Tuist 專屬變數覆寫
- 依賴合理的預設值，無需任何設定

## 常見使用情境{#common-use-cases}

### 依專案隔離 Tuist{#isolating-tuist-per-project}

您可能需要針對每個專案獨立管理 Tuist 的快取與狀態：

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD 環境{#ci-cd-environments}

在 CI 環境中，您可能需要使用臨時目錄：

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

### 使用隔離目錄進行除錯{#debugging-with-isolated-directories}

在除錯問題時，您可能需要一個乾淨的起點：

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
