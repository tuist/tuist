---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# 目录{#directories}

Tuist 根据 [XDG
基础目录规范](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
在系统多个目录中组织文件，提供管理配置、缓存和状态文件的规范化方式。

## 支持的环境变量{#supported-environment-variables}

Tuist同时支持标准XDG变量与Tuist专属前缀变体。Tuist专属变体（以`TUIST_` 开头）具有优先级，可实现与其他应用程序的独立配置。

### 配置目录{#configuration-directory}

**环境变量：**
- `TUIST_XDG_CONFIG_HOME` (优先级最高)
- `XDG_CONFIG_HOME`

**默认值：** `~/.config/tuist`

**用途：**
- 服务器凭证（`credentials/{host}.json` ）

**示例：**
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
- `TUIST_XDG_CACHE_HOME` (优先级最高)
- `XDG_CACHE_HOME`

**默认值：** `~/.cache/tuist`

**用途：**
- **插件** ：已下载并编译的插件缓存
- **ProjectDescriptionHelpers**: 编译后的项目描述辅助工具
- **清单文件**: 缓存的清单文件
- **项目**: 自动生成的项目缓存
- **编辑项目** ：编辑命令缓存
- **运行**: 测试与构建运行分析数据
- **二进制文件**: 构建二进制构建产物（不可跨环境共享）
- **SelectiveTests**: 选择性测试缓存

**示例：**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### 州目录{#state-directory}

**环境变量：**
- `TUIST_XDG_STATE_HOME` (优先级最高)
- `XDG_STATE_HOME`

**默认值：** `~/.local/state/tuist`

**用途：**
- **日志**: 日志文件 (`logs/{uuid}.log`)
- **锁** ：认证锁文件（`{handle}.sock` ）

**示例：**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## 优先级顺序{#precedence-order}

在确定使用哪个目录时，Tuist按以下顺序检查环境变量：

1. **Tuist专属变量** （例如：`TUIST_XDG_CONFIG_HOME` ）
2. **标准XDG变量** （例如：`XDG_CONFIG_HOME` ）
3. **默认位置：** （例如：`~/.config/tuist` ）

这将使您能够：
- 使用标准XDG变量来统一管理所有应用程序
- 若需为Tuist设置不同位置，请使用Tuist专属变量覆盖
- 无需任何配置，直接采用合理的默认设置

## 常见使用场景{#common-use-cases}

### 按项目隔离 Tuist{#isolating-tuist-per-project}

您可能需要按项目隔离 Tuist 的缓存和状态：

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD 环境{#ci-cd-environments}

在CI环境中，建议使用临时目录：

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

在调试问题时，您可能需要一个干净的起点：

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
