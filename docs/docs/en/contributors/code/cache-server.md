---
{
  "title": "Cache Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Cache Server."
}
---
# Cache Server {#cache-server}

Source: [github.com/tuist/tuist/tree/main/cache](https://github.com/tuist/tuist/tree/main/cache)

## What it is for {#what-it-is-for}

The cache server is a separate cache service that provides storage and retrieval for Tuist. Some Tuist capabilities are served through it to reduce latency, and it authenticates via the Tuist server API.

## How to contribute {#how-to-contribute}

### Set up locally {#set-up-locally}

```bash
cd cache
mise install
mix deps.get
mix phx.server
```

The cache server expects a <LocalizedLink href="/contributors/code/server">Tuist server</LocalizedLink> running at `http://localhost:8080`.

### Nginx and local setup {#nginx-and-local-setup}

In production the cache service is fronted by nginx to optimize read performance. Local development with `mix phx.server` does not use nginx. If you want to test the full nginx + release setup locally, use `cache/docker-compose.yml`, which starts the cache release and nginx wired through a Unix socket.

### Tests {#tests}

```bash
mix test
```
