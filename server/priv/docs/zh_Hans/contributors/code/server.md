---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "为 Tuist Server 做出贡献。"
}
---
# 服务器 {#server}

源码：[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## 用途 {#what-it-is-for}

该服务器为 Tuist 的服务端功能提供支持，包括身份验证、账户与项目管理、缓存存储、洞察分析、预览、注册中心以及集成（GitHub、Slack 和 SSO）。它是一个基于 Phoenix/Elixir 的应用，使用 Postgres 和 ClickHouse。

## 如何贡献 {#how-to-contribute}

向服务器贡献代码需要签署 CLA（`server/CLA.md`）。

### 本地设置 {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

在浏览器中打开 `http://localhost:8080`。在开发环境中，登录页面包含一个**以测试用户身份登录**按钮，可使用预置账户（`tuistrocks@tuist.dev` / `tuistrocks`）登录。

> [!NOTE]
> 内部开发者通过 fnox 从 1Password 加载开发密钥——`mise run dev`将服务器包裹在`fnox exec`中运行（参见`server/fnox.toml`）。外部贡献者无需访问 1Password；服务器可在没有它的情况下本地运行。OAuth、Stripe 及其他第三方集成将被禁用，但核心功能仍可正常使用。

### 本地 Helm 测试 {#local-helm-testing}

你可以使用[kind](https://kind.sigs.k8s.io/)和内置的 mise 任务在本地机器上启动完整的技术栈。这会在本地构建 Docker 镜像、创建 kind 集群、安装 Chart，并自动为所有服务设置端口转发：

```bash
# Deploy everything (builds images from source)
mise run helm:up --license "YOUR_LICENSE_KEY"

# Include the observability stack (Grafana, Prometheus, Loki, Tempo)
mise run helm:up --license "YOUR_LICENSE_KEY" --observability

# Check status
mise run helm:status

# Tear down
mise run helm:down
```

**前置条件：**`docker`、`kind`、`helm`和`kubectl`。

### 测试与格式化 {#tests-and-formatting}

- 测试：`mix test`
- 格式化：`mise run format`
