---
{
  "title": "伺服器",
  "titleTemplate": ":title · 程式碼 · 貢獻者 · Tuist",
  "description": "為 Tuist Server 做出貢獻。"
}
---
# 伺服器 {#server}

來源：[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## 用途 {#what-it-is-for}

此伺服器支援 Tuist 的伺服器端功能，包括身分驗證、帳號與專案、快取儲存、分析洞察、預覽、註冊表，以及整合（GitHub、Slack 和 SSO）。它是一個基於 Phoenix/Elixir 的應用程式，搭配 Postgres 與 ClickHouse。

## 如何貢獻 {#how-to-contribute}

對伺服器的貢獻需要簽署 CLA（`server/CLA.md`）。

### 本機設定 {#set-up-locally}

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

在瀏覽器中開啟 `http://localhost:8080`。在開發環境中，登入頁面包含一個**以測試使用者身分登入**按鈕，可使用預先建立的帳號（`tuistrocks@tuist.dev` / `tuistrocks`）為你登入。

> [!NOTE]
> 內部開發人員透過 fnox 從 1Password 載入開發密鑰 — `mise run dev` 將伺服器包裝在 `fnox exec` 中（請參閱 `server/fnox.toml`）。外部貢獻者不需要存取 1Password；伺服器可在沒有它的情況下於本機執行。OAuth、Stripe 與其他第三方整合將會停用，但核心功能仍可正常運作。

### 本機 Helm 測試 {#local-helm-testing}

你可以使用 [kind](https://kind.sigs.k8s.io/) 與內建的 mise 任務，在本機啟動完整堆疊。這會在本機建置 Docker 映像、建立 kind 叢集、安裝 Helm Chart，並自動為所有服務進行連接埠轉送：

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

**必要條件：**`docker`、`kind`、`helm` 與 `kubectl`。

### 測試與格式化 {#tests-and-formatting}

- 測試：`mix test`
- 格式化：`mise run format`
