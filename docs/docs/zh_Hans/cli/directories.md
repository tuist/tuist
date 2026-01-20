---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# 目录{#directories}

Tuist 遵循 [XDG
基本目录规范](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)，在系统中的多个目录中组织文件。这为管理配置、缓存和状态文件提供了一种简洁、标准的方式。

## 支持的环境变量{#supported-environment-variables}

Tuist 既支持标准 XDG 变量，也支持 Tuist 特有的前缀变量。Tuist 专用变量（前缀为`TUIST_` ）优先，允许您将 Tuist
与其他应用程序分开配置。

### 配置目录{#configuration-directory}

**环境变量：**
- `TUIST_XDG_CONFIG_HOME` （优先）。
- `xdg_config_home`

**默认值：** `~/.config/tuist`

**用于：**
- 服务器凭据 (`credentials/{host}.json`)

**例如**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### 缓存目录{#cache-directory}

**环境变量：**
- `TUIST_XDG_CACHE_HOME` （优先）。
- `XDG_CACHE_HOME`

**默认值：** `~/.cache/tuist`

**用于：**
- **插件** ：已下载和编译的插件缓存
- **ProjectDescriptionHelpers** ：编译的项目描述助手
- **清单** ：缓存清单文件
- **项目** ：生成自动化项目缓存
- **编辑项目** ：编辑命令缓存
- **运行** ：测试和构建运行分析数据
- **二进制文件** ：构建工件二进制文件（不可跨环境共享）
- **SelectiveTests** ：选择性测试缓存

**例如**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### 国家目录{#state-directory}

**环境变量：**
- `TUIST_XDG_STATE_HOME` （优先使用）
- `XDG_STATE_HOME`

**默认值：** `~/.local/state/tuist`

**用于：**
- **日志** ：日志文件 (`logs/{uuid}.log`)
- **锁** ：身份验证锁文件 (`{handle}.sock`)

**例如**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## 优先顺序{#precedence-order}

在确定使用哪个目录时，Tuist 会按以下顺序检查环境变量：

1. **特定于 Tuist 的变量** （例如，`TUIST_XDG_CONFIG_HOME`)
2. **标准 XDG 变量** （如`XDG_CONFIG_HOME`)
3. **默认位置** （例如，`~/.config/tuist`)

这样您就可以
- 使用标准的 XDG 变量来统一组织所有应用程序
- 当需要 Tuist 的不同位置时，使用 Tuist 专用变量覆盖
- 依靠合理的默认设置，无需任何配置

## 常见用例{#common-use-cases}

### 按项目隔离图易斯特{#isolating-tuist-per-project}

您可能需要在每个项目中隔离 Tuist 的缓存和状态：

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD 环境{#ci-cd-environments}

在 CI 环境中，您可能需要使用临时目录：

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

### 使用隔离目录进行调试{#debugging-with-isolated-directories}

在调试问题时，你可能需要一块干净的石板：

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
