---
{
  "title": "HTTP 代理",
  "titleTemplate": ":title | 整合 | 指南 | Tuist",
  "description": "了解當設定 HTTPS_PROXY 或 HTTP_PROXY 時，Tuist 如何透過企業代理伺服器路由其 HTTP 流量。"
}
---
# HTTP 代理 {#http-proxy}

當環境中設定了 `HTTPS_PROXY` 或 `HTTP_PROXY` 時，Tuist 會自動將其管理的 HTTP 連線透過該代理伺服器轉送。這適用於 Tuist CLI 與 Tuist Gradle 外掛程式，無需額外設定。

此行為符合 `curl`、`git` 與大多數開發者工具所使用的慣例，因此任何已為其他工具設定這些變數的環境，都能直接與 Tuist 搭配使用。

## 哪些連線會經過代理 {#what-is-proxied}

只有由 Tuist 擁有的 HTTP 用戶端會透過代理伺服器轉送：

- 快取、預覽、分析與註冊表端點，
- 以及 Gradle 外掛程式呼叫 Tuist 服務的回呼（遠端建置快取、建置洞察、測試洞察、測試隔離、測試分片）。

## 變數查找順序 {#variable-lookup-order}

Tuist 會依下列順序讀取第一個非空值：

1. `HTTPS_PROXY`
2. `https_proxy`
3. `HTTP_PROXY`
4. `http_proxy`

該值必須是類似 `http://proxy.corp:8080` 的 URL。支援內嵌憑證（`http://user:password@proxy.corp:8080`）。
