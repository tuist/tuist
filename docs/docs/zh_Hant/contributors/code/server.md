---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# 伺服器{#server}

來源：[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## 用途說明{#what-it-is-for}

此伺服器驅動 Tuist 的伺服器端功能，包含驗證、帳戶與專案管理、快取儲存、分析洞察、預覽功能、註冊表及整合服務（GitHub、Slack 與
SSO）。其架構為 Phoenix/Elixir 應用程式，搭配 Postgres 與 ClickHouse 資料庫。

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB 已被廢棄並將被移除。若您目前仍需使用它進行本地設定或資料遷移，請參閱 [TimescaleDB
安裝文件](https://docs.timescale.com/self-hosted/latest/install/installation-macos/)。
<!-- -->
:::

## 如何貢獻{#how-to-contribute}

對伺服器的貢獻需簽署貢獻者協議 (CLA) (`server/CLA.md`)。

### 在本地端設定{#set-up-locally}

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

> [!注意] 第一方開發者會從`priv/secrets/dev.key 載入加密密鑰`
> 。外部貢獻者不會擁有該密鑰，這沒問題。伺服器仍可透過`TUIST_SECRET_KEY_BASE` 本地運行，但 OAuth、Stripe
> 及其他整合功能將保持停用狀態。

### 測試與格式設定{#tests-and-formatting}

- 測試：`混合測試`
- 格式：`mise run format`
