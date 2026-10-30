---
{
  "title": "HTTP 代理",
  "titleTemplate": ":title | 集成 | 指南 | Tuist",
  "description": "了解当设置 HTTPS_PROXY 或 HTTP_PROXY 时，Tuist 如何通过企业代理路由其 HTTP 流量。"
}
---
# HTTP 代理 {#http-proxy}

当环境中设置了 `HTTPS_PROXY` 或 `HTTP_PROXY` 时，Tuist 会自动将其管理的 HTTP 连接通过该代理进行路由。这适用于 Tuist CLI 和 Tuist Gradle 插件，无需额外配置。

此行为与 `curl`、`git` 以及大多数开发者工具使用的约定一致，因此任何已为其他工具设置这些变量的环境都可以开箱即用地与 Tuist 配合使用。

## 哪些内容会经过代理 {#what-is-proxied}

只有 Tuist 拥有的 HTTP 客户端会通过代理进行路由：

- 缓存、预览、分析和注册表端点，
- 以及 Gradle 插件对 Tuist 服务的调用（远程构建缓存、构建洞察、测试洞察、测试隔离、测试分片）。

## 变量查找顺序 {#variable-lookup-order}

Tuist 按以下顺序读取第一个非空值：

1. `HTTPS_PROXY`
2. `https_proxy`
3. `HTTP_PROXY`
4. `http_proxy`

该值必须是 URL，例如 `http://proxy.corp:8080`。支持内联凭据（`http://user:password@proxy.corp:8080`）。
