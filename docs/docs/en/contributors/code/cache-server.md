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

The cache server is a separate cache service that provides cache storage and retrieval. It serves CAS artifacts and key-value metadata and authenticates via the Tuist server API.

## How to contribute {#how-to-contribute}

### Set up locally {#set-up-locally}

```bash
cd cache
mise install
mix deps.get
mix phx.server
```

The cache server expects a <LocalizedLink href="/contributors/code/server">Tuist server</LocalizedLink> running at `http://localhost:8080`.

Authentication uses `TUIST_CACHE_API_KEY`. In development, the server and cache default to a shared value, so you only need to set it if you want to override the default.

### Tests {#tests}

```bash
mix test
```
