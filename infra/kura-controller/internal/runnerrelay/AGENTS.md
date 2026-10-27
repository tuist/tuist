# Linux ordinary cache relay

The account flag selects an endpoint at claim, never runner capacity. This
relay keeps the ordinary endpoint outside OVH's host-wide private routes.
`cmd/runner-cache-relay` must refuse non-Hetzner or private-network nodes; Helm
places two replicas on separate general nodes. Never deploy this on an OVH
cache/runner host, or silently fall back to the direct cache when it fails.

The controller owns alias Services for public KuraInstances. Their names are
`wan-` plus the first 32 lowercase hex characters of SHA-256 of the exact primary
Service name. Keep that contract aligned with the Elixir endpoint resolver,
including moved `-m` instances. Owners handle cleanup; disabling preparation
retains existing aliases until jobs using them finish.

Resolve only watched, labeled, owner-bound aliases in the configured namespace.
Never accept caller-supplied upstream URLs or forward to arbitrary Services.
Stream HTTP and h2c gRPC bodies without buffering complete artifacts. Preserve
Kura authentication, methods, paths, query strings, statuses and trailers.
Suppress endpoint redirects and reject unexpected redirects so a client cannot
silently leave the ordinary path. Do not log credentials or artifact paths.

Run `go test ./internal/runnerrelay ./cmd/runner-cache-relay ./controllers`.
Unit tests do not establish physical transport: qualify both endpoints on the
same enrolled runner with interface captures before account enrollment.
