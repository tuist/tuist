---
{
  "title": "伺服器",
  "titleTemplate": ":title · 程式碼 · 貢獻者 · Tuist",
  "description": "為 Tuist Server 作出貢獻。"
}
---
# 伺服器 {#server}

來源：[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## 用途 {#what-it-is-for}

伺服器支援 Tuist 嘅伺服器端功能，包括認證、帳戶同專案、快取儲存、洞察分析、預覽、註冊中心，以及整合（GitHub、Slack 同 SSO）。佢係一個基於 Phoenix/Elixir 嘅應用程式，使用 Postgres 同 ClickHouse。

## 如何貢獻 {#how-to-contribute}

貢獻伺服器代碼需要簽署 CLA (`server/CLA.md`)。

### 本地設定 {#set-up-locally}

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

喺瀏覽器開啟 `http://localhost:8080`。開發環境下，登入頁面包含一個 **以測試用戶身份登入** 按鈕，會用預設帳戶登入你 (`tuistrocks@tuist.dev` / `tuistrocks`)。

> [!NOTE]
> 內部開發人員透過 fnox 從 1Password 載入開發密鑰 — `mise run dev` 將伺服器包裝喺 `fnox exec` 入面（見 `server/fnox.toml`）。外部貢獻者唔需要 1Password 存取權限；伺服器可以喺本地運行而唔需要佢。OAuth、Stripe 同其他第三方整合會被停用，但核心功能仍然運作。

### 本地 Helm 測試 {#local-helm-testing}

你可以用 [kind](https://kind.sigs.k8s.io/) 同內置嘅 mise 任務喺你部機上啟動完整堆疊。呢個過程會本地構建 Docker 映像、建立 kind 叢集、安裝 chart，並自動轉發所有服務嘅端口：

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

**前置條件：** `docker`、`kind`、`helm` 同 `kubectl`。

### 測試同格式化 {#tests-and-formatting}

- 測試：`mix test`
- 格式化：`mise run format`
