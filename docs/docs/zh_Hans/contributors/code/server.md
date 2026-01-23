---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# 服务器{#server}

来源：[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## 用途说明{#what-it-is-for}

该服务器为Tuist提供服务器端功能支持，包括身份验证、账户与项目管理、缓存存储、数据洞察、预览功能、注册表及集成服务（GitHub、Slack和单点登录）。该应用基于Phoenix/Elixir框架构建，采用Postgres和ClickHouse数据库。

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB 已弃用并将被移除。若当前仍需用于本地部署或数据迁移，请参照[TimescaleDB
安装文档](https://docs.timescale.com/self-hosted/latest/install/installation-macos/)进行操作。
<!-- -->
:::

## 如何贡献{#how-to-contribute}

向服务器提交贡献需签署CLA（`server/CLA.md` ）。

### 本地设置{#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Minimal secrets
export TUIST_SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

> [!NOTE] 第一方开发者从`priv/secrets/dev.key`
> 加载加密密钥。外部贡献者无需该密钥，系统仍可通过`TUIST_SECRET_KEY_BASE` 本地运行，但 OAuth、Stripe
> 等集成功能将保持禁用状态。

### 测试与格式{#tests-and-formatting}

- 测试：`混合测试`
- 格式：`mise run format`
