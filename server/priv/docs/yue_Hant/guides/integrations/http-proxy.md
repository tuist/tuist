---
{
  "title": "HTTP proxy",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "了解當設定咗 HTTPS_PROXY 或 HTTP_PROXY 時，Tuist 點樣透過企業代理伺服器路由其 HTTP 流量。"
}
---
# HTTP 代理 {#http-proxy}

當環境中設定咗 `HTTPS_PROXY` 或 `HTTP_PROXY`，Tuist 會自動將佢管理嘅 HTTP 連線透過該代理伺服器轉發。這適用於 Tuist CLI 同 Tuist Gradle 插件，無需額外設定。

此行為符合 `curl`、`git` 同大多數開發者工具所用嘅慣例，所以任何已經為其他工具設定咗呢啲變數嘅環境，都可以直接同 Tuist 配合使用。

## 乜嘢會被代理 {#what-is-proxied}

只有 Tuist 擁有嘅 HTTP 客戶端會透過代理伺服器轉發：

- 快取、預覽、分析同註冊中心端點，
- 以及 Gradle 插件調用 Tuist 服務嘅請求（遠程構建快取、構建洞察、測試洞察、測試隔離、測試分片）。

## 變數查找順序 {#variable-lookup-order}

Tuist 會按以下順序讀取第一個非空值：

1. `HTTPS_PROXY`
2. `https_proxy`
3. `HTTP_PROXY`
4. `http_proxy`

值必須係 URL，例如 `http://proxy.corp:8080`。內嵌憑證（`http://user:password@proxy.corp:8080`）會被支援。
