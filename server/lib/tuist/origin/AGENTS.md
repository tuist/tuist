# Cursor Origin

Owns Origin app authentication, signed installation receipts/webhooks, account
installations, and PR report transport. Origin is a forge, not a runner coordinator:
Tuist provides compute through Origin's Buildkite integration using the existing
Buildkite runner lifecycle.

- Only native Origin repositories accept app comments/checks. GitHub mirrors keep
  GitHub feedback and CI.
- Verify receipt issuer, audience, algorithm, type and expiry; require explicit
  authorized Tuist account confirmation before linking marketplace installs.
- Webhooks sign the lowercase SHA-256 hex digest of id.timestamp.raw-body with
  Ed25519. Routing headers are not authoritative; use the signed envelope.
- Mint installation tokens just in time. Never cache them on GitHub's schedule or
  hand app signing keys to runners.
- `RunnerCheckout` binds a separate twelve-hour grant to the server-fetched
  Buildkite job/repository and account installation. Refresh only for active
  jobs and currently accessible native repositories, attenuating every token
  to that one repository and contents-read. Report tokens cannot authorize checkout.
- Reconcile lifecycle changes against the current API state, not reordered event
  snapshots. Report errors must reach Oban for retry.
- Keep customer installation/link data in server/data-export.md.
