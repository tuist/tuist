---
{
  "title": "目錄",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解 Tuist 如何組織其設定、快取和狀態目錄。"
}
---
# 目錄 {#directories}

Tuist 會按照 [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)，將檔案整理到系統中的多個目錄。這提供了一種清晰、標準的方式來管理設定、快取和狀態檔案。

## 支援的環境變數 {#supported-environment-variables}

Tuist 同時支援標準 XDG 變數和帶有 Tuist 專屬前綴的變體。Tuist 專屬變體（以 `TUIST_` 為前綴）具有較高優先級，讓你可以獨立於其他應用程式來設定 Tuist。

### 設定目錄 {#configuration-directory}

**環境變數：**
- `TUIST_XDG_CONFIG_HOME`（具有較高優先級）
- `XDG_CONFIG_HOME`

**預設值：** `~/.config/tuist`

**用途：**
- 伺服器憑證（`credentials/{host}.json`）

**範例：**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### 快取目錄 {#cache-directory}

**環境變數：**
- `TUIST_XDG_CACHE_HOME`（具有較高優先級）
- `XDG_CACHE_HOME`

**預設值：** `~/.cache/tuist`

**用途：**
- **Plugins**：已下載並編譯的外掛程式快取
- **ProjectDescriptionHelpers**：已編譯的專案描述輔助工具
- **Manifests**：已快取的 manifest 檔案
- **Projects**：已產生的自動化專案快取
- **EditProjects**：edit 指令的快取
- **Runs**：測試和建構執行的分析資料
- **Binaries**：建構產物二進位檔（無法在不同環境之間共用）
- **SelectiveTests**：選擇性測試快取

**範例：**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### 狀態目錄 {#state-directory}

**環境變數：**
- `TUIST_XDG_STATE_HOME`（具有較高優先級）
- `XDG_STATE_HOME`

**預設值：** `~/.local/state/tuist`

**用途：**
- **Sessions**：工作階段記錄和網路錄製（`sessions/{uuid}/`）
- **Locks**：驗證鎖定檔案（`{handle}.sock`）

**範例：**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## 優先順序 {#precedence-order}

在決定使用哪個目錄時，Tuist 會按以下順序檢查環境變數：

1. **Tuist 專屬變數**（例如 `TUIST_XDG_CONFIG_HOME`）
2. **標準 XDG 變數**（例如 `XDG_CONFIG_HOME`）
3. **預設位置**（例如 `~/.config/tuist`）

這讓你可以：
- 使用標準 XDG 變數來一致地組織所有應用程式
- 當你需要為 Tuist 使用不同位置時，以 Tuist 專屬變數覆寫
- 無需任何設定即可依賴合理的預設值

## 常見使用案例 {#common-use-cases}

### 按專案隔離 Tuist {#isolating-tuist-per-project}

你可能希望按專案隔離 Tuist 的快取和狀態：

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD 環境 {#ci-cd-environments}

在 CI 環境中，你可能希望使用臨時目錄：

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

### 使用隔離目錄進行除錯 {#debugging-with-isolated-directories}

在除錯問題時，你可能希望從乾淨的狀態開始：

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
