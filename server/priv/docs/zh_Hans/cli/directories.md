---
{
  "title": "目录",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解 Tuist 如何组织其配置、缓存和状态目录。"
}
---
# 目录 {#directories}

Tuist 遵循 [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)，将文件组织在系统上的多个目录中。这提供了一种清晰、标准的方式来管理配置、缓存和状态文件。

## 支持的环境变量 {#supported-environment-variables}

Tuist 同时支持标准 XDG 变量和带有 Tuist 特定前缀的变体。Tuist 特定变体（以 `TUIST_` 为前缀）具有更高优先级，允许你独立于其他应用程序配置 Tuist。

### 配置目录 {#configuration-directory}

**环境变量：**
- `TUIST_XDG_CONFIG_HOME`（具有更高优先级）
- `XDG_CONFIG_HOME`

**默认值：** `~/.config/tuist`

**用途：**
- 服务器凭据（`credentials/{host}.json`）

**示例：**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### 缓存目录 {#cache-directory}

**环境变量：**
- `TUIST_XDG_CACHE_HOME`（具有更高优先级）
- `XDG_CACHE_HOME`

**默认值：** `~/.cache/tuist`

**用途：**
- **Plugins**：已下载并编译的插件缓存
- **ProjectDescriptionHelpers**：已编译的项目描述辅助代码
- **Manifests**：缓存的清单文件
- **Projects**：生成的自动化项目缓存
- **EditProjects**：edit 命令的缓存
- **Runs**：测试和构建运行的分析数据
- **Binaries**：构建产物二进制文件（无法在不同环境间共享）
- **SelectiveTests**：选择性测试缓存

**示例：**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### 状态目录 {#state-directory}

**环境变量：**
- `TUIST_XDG_STATE_HOME`（具有更高优先级）
- `XDG_STATE_HOME`

**默认值：** `~/.local/state/tuist`

**用途：**
- **Sessions**：会话日志和网络记录（`sessions/{uuid}/`）
- **Locks**：身份验证锁文件（`{handle}.sock`）

**示例：**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## 优先级顺序 {#precedence-order}

在确定使用哪个目录时，Tuist 会按以下顺序检查环境变量：

1. **Tuist 特定变量**（例如 `TUIST_XDG_CONFIG_HOME`）
2. **标准 XDG 变量**（例如 `XDG_CONFIG_HOME`）
3. **默认位置**（例如 `~/.config/tuist`）

这使你能够：
- 使用标准 XDG 变量一致地组织所有应用程序
- 当需要为 Tuist 使用不同位置时，可通过 Tuist 特定变量进行覆盖
- 无需任何配置即可依赖合理的默认值

## 常见用例 {#common-use-cases}

### 按项目隔离 Tuist {#isolating-tuist-per-project}

你可能希望按项目隔离 Tuist 的缓存和状态：

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD 环境 {#ci-cd-environments}

在 CI 环境中，你可能希望使用临时目录：

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

### 使用隔离目录进行调试 {#debugging-with-isolated-directories}

在调试问题时，你可能希望从头开始：

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
