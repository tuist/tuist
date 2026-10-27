---
{
  "title": "HTTP proxy",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how Tuist routes its HTTP traffic through a corporate proxy when HTTPS_PROXY or HTTP_PROXY is set."
}
---
# HTTP proxy {#http-proxy}

When `HTTPS_PROXY` or `HTTP_PROXY` is set in the environment, Tuist automatically routes the HTTP connections it manages through that proxy. This applies to both the Tuist CLI and the Tuist Gradle plugin, with no extra configuration required.

The behavior matches the convention used by `curl`, `git`, and most developer tools, so any environment that already sets these variables for other tooling works with Tuist out of the box.

## What is proxied {#what-is-proxied}

Only the HTTP clients Tuist owns are routed through the proxy:

- the cache, previews, analytics, and registry endpoints,
- and the calls the Gradle plugin makes back to Tuist services (remote build cache, build insights, test insights, test quarantine, test sharding).

## Variable lookup order {#variable-lookup-order}

Tuist reads the first non-empty value in this order:

1. `HTTPS_PROXY`
2. `https_proxy`
3. `HTTP_PROXY`
4. `http_proxy`

The value must be a URL such as `http://proxy.corp:8080`. Inline credentials (`http://user:password@proxy.corp:8080`) are honored.
