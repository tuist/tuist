# Server Configuration

This directory holds Phoenix configuration for the server.

## Responsibilities
- Environment-specific configuration (dev, test, prod).
- Runtime config and endpoint settings.
- Marketing's esbuild `noora/hooks` alias resolves individual Noora hook sources
  so unused charting and form runtimes stay out of the marketing bundle.
- The `newsletter` esbuild profile builds the verification page's dedicated
  assets; both asset aliases and the development watchers include it.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`
