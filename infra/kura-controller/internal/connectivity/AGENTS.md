# Fixed connectivity diagnostic profile

This package is used only by `cmd/connectivity-probe`, a log-only sidecar opted
in through controller deployment configuration. See
[`../../connectivity-diagnostics.md`](../../connectivity-diagnostics.md) for the
threat model, bounds, operational tradeoffs, and rollout procedure.

Keep the destination, unauthenticated GET, and `/ready` path fixed in code.
Do not add a listener, exec wrapper, configurable URL/headers, credentials,
response content logging, redirects, proxy support, or mounts. New destinations
need explicit review of both their ownership and GET side effects. Preserve
bounded serial work, resolver/address validation, deadlines, and resource limits.
The read-only role must only consume logs; it must never need to trigger work or
change a workload. Run the package's race-enabled tests and controller rendering
tests when changing this boundary.
