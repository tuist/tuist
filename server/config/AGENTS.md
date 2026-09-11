# Server Configuration

This directory holds Phoenix configuration for the server.

## Responsibilities
- Environment-specific configuration (dev, test, prod).
- Runtime config and endpoint settings.
- Marketing's esbuild `noora/hooks` alias resolves individual Noora hook sources
  so unused charting and form runtimes stay out of the marketing bundle.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`

- GitLab coordinator polling uses the dedicated `runner_gitlab` queue on web nodes; network waits must not occupy the general `default` queue.
