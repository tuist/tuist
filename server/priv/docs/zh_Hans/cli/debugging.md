---
{
  "title": "调试",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解如何通过日志和网络记录来调试 Tuist 的问题。"
}
---
# 调试 {#debugging}

当命令未按预期行为时，Tuist 提供了多种工具来帮助你诊断问题。

> [!WARNING]
> 会话数据可能包含敏感信息，例如文件路径、项目名称以及请求/响应体。虽然敏感标头（如 Authorization）会被脱敏处理，但在与他人共享会话数据时仍需谨慎。


## 会话数据 {#session-data}

如果命令调用未产生预期结果，你可以通过检查会话数据来诊断问题。CLI 会将日志转发到 [OSLog](https://developer.apple.com/documentation/os/oslog) 和文件系统。

每次运行时，它都会在 `$XDG_STATE_HOME/tuist/sessions/{uuid}/` 创建一个会话目录，如果未设置环境变量，`$XDG_STATE_HOME` 的值为 `~/.local/state`。你还可以使用 `$TUIST_XDG_STATE_HOME` 设置 Tuist 专用的状态目录，其优先级高于 `$XDG_STATE_HOME`。

每个会话目录包含：
- **`logs.txt`** - CLI 会话的文本日志
- **`network.har`** - [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) 文件，包含会话期间发出的所有网络请求和响应

### 可视化 HAR 文件 {#visualizing-har-files}

HAR 文件记录了会话期间发出的所有 HTTP 请求和响应，这对于调试服务器通信问题非常有用。你可以使用多种工具打开 HAR 文件：

- **[Proxyman](https://proxyman.io/)**：一款原生 macOS 应用，用于查看和分析 HTTP 流量。通过 File > Import 导入 HAR 文件。
- **浏览器开发者工具**：Chrome、Firefox 和 Safari 均支持在其 Network 标签页中导入 HAR 文件。
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**：一个基于 Web 的 HAR 文件查看器。

> [!TIP]
> 在 <.localized_link href="/cli/directories">目录文档</.localized_link> 中了解更多关于 Tuist 目录组织以及如何配置自定义目录的信息。


默认情况下，当执行意外退出时，CLI 会输出会话路径。如果没有输出，你可以在上述路径（即最新的会话目录）中找到会话数据。

超过 5 天的会话目录会自动清理。默认情况下，Tuist 最多保留 50 个非活动会话目录，同时保留由当前运行的 Tuist 进程拥有的会话。在使用相同状态目录运行大量 Tuist 命令的 CI 环境中，你可以通过 `TUIST_SESSION_MAX_SESSIONS` 提高非活动会话的上限，例如 `TUIST_SESSION_MAX_SESSIONS=200`。无效值、零值和负值将被忽略，Tuist 将回退到默认值 50。

### 持续集成 {#diagnose-issues-using-logs-ci}

在环境可丢弃的 CI 中，你可能希望配置 CI 流水线以导出 Tuist 会话数据。导出构件是各 CI 服务的常见功能，具体配置取决于你使用的服务。例如，在 GitHub Actions 中，你可以使用 `actions/upload-artifact` action 将会话数据作为构件上传：

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist session data
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-sessions
          path: /tmp/tuist/sessions/
```

### Xcode 缓存调试 {#cache-daemon-debugging}

要调试 Xcode 缓存问题，请在运行 `tuist setup cache` 和构建时将 `TUIST_CAS_LOG` 设置为文件路径。Tuist 会将缓存统计信息和错误追加到该文件中：

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

在 CI 上，Tuist 会将此日志写入 `~/.local/state/tuist/cas.log`，无需任何配置。

## 调整网络超时和重试 {#tuning-network-timeouts}

Tuist 的所有 [超文本传输协议 (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) 流量，包括服务器调用、注册表、预览和缓存构件传输，都通过具有合理默认值的共享 `URLSession` 进行。在网络路径缓慢或拥塞的情况下（例如，通过企业代理访问对象存储的自托管设置），单个请求可能会因资源耗尽而在完成前命中资源超时。特别是对于缓存下载，命中超时会导致 Tuist 回退到从源代码构建模块，这比稍作等待以获取缓存二进制文件要昂贵得多。你可以通过环境变量调整底层设置，当变量未设置或设置为无效值时将应用默认值：

```bash
# Maximum time (in seconds) a single resource transfer can take before it's cancelled
# (default: 90, or 600 for whole-file transfers such as test-product shard artifacts)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE=600

# Maximum time (in seconds) to wait for new data on an existing request (default: 120)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST=300

# Maximum number of simultaneous connections per host (default: 20)
export TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST=40

# Maximum retries after the initial attempt (default: 3, maximum: 10)
export TUIST_HTTP_MAXIMUM_RETRY_COUNT=1

# Initial exponential backoff delay in milliseconds (default: 100, maximum: 30000)
export TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS=250
```

资源超时是整个传输过程的墙上时钟上限，而非停滞保护，因此它必须足够大以容纳你传输的最大构件。整文件传输（例如分片下载的测试产品）因此默认为 10 分钟而不是 90 秒，并且如果没有新数据，停滞的传输在 `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST` 后仍然会失败。这些传输仅读取 `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` 以提高其上限，绝不会将其降低到 10 分钟以下，因此选择使缓存请求快速失败的值不会同时取消分片对其测试产品的下载。提高 `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` 可以让可恢复但缓慢的下载完成而不是超时。对于缓存下载，这意味着实现缓存命中而不是回退到从源代码构建，因此请有意提高它：保持缓慢缓存下载活动的相同值也会延迟回退到从源代码构建。降低 `TUIST_HTTP_MAXIMUM_RETRY_COUNT` 可以防止较长的超时在多次尝试中成倍增加最坏情况下的等待时间。重试延迟在每次失败后加倍，包括最多一个基础延迟的随机抖动，且永远不会超过 30 秒。

## 信任自定义 CA 证书 {#trusting-a-custom-ca-certificate}

默认情况下，Tuist 会根据操作系统的根存储验证 TLS 证书。当你运行使用私有证书颁发机构的自托管 Tuist 或 Kura 服务器时，Tuist 也需要信任该 CA。在系统钥匙串中安装根证书（并将其标记为受信任用于 SSL）是标准方法，但这在无头 CI 主机上通常不切实际，因为没有 GUI 会话或移动设备管理 (MDM) 来设置信任位。

在这些情况下，你可以直接让 Tuist 指向 CA 证书捆绑包。捆绑包可以是 PEM（一个或多个连接的 `-----BEGIN CERTIFICATE-----` 块）或单个 DER 文件。系统根存储与其一起保持受信任，因此公共证书继续正常验证，且证书评估永远不会被绕过。

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

你也可以在 <.localized_link href="/references/tuist-toml">配置文件</.localized_link> 中声明它：

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

`TUIST_CA_CERTIFICATE` 环境变量优先于配置文件，这使得将其作为 CI 机密提供非常方便，而无需更改提交的清单。
