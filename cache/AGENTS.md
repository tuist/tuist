# Tuist Cache Service (Elixir/Phoenix)

This service provides caching infrastructure for Tuist. It shares tooling and conventions with the Tuist Server.

## Key Boundaries
- Web/API layer: `cache/lib/cache_web`
- Cache domain and storage: `cache/lib/cache`
- Nginx and host-level config: `cache/platform`

## Related Context (Downlinks)
- Cache web layer: `cache/lib/cache_web/AGENTS.md`
- Cache domain and storage: `cache/lib/cache/AGENTS.md`
- Platform/nginx config: `cache/platform/AGENTS.md`
- Server conventions and tooling: `server/AGENTS.md`
