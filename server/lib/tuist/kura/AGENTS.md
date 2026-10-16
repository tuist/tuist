# Kura control plane

- `Origins` and `Demand` sort bulk upsert rows by their full conflict keys before
  insertion so concurrent overlapping batches acquire locks in a consistent
  order. Keep this ordering at the write boundary, including backfills and
  write-through calls; sorted account key-share locks alone do not order the
  subsequent rollup/lifecycle writes.

- `kura_positive_fence` is default off and changes both `servingMode` and the
  manifest revision. Controller activation is sticky: disabling the account
  flag cannot remove the serving rollback floor or restore legacy selection.
  See [serving authority](../../../../../infra/kura-controller/serving-authority.md).

- Capacity counts every node-local volume on a region's nodes that no claim is bound to (a quarantined replica's retained volume, a Released volume awaiting deletion) at its provisioned size, in the region total and in the node's headroom. No pod requests that disk, so the scheduler would otherwise hand it out again. Failing to list volumes leaves the reading unknown, the same as failing to list pods.

- Demand has two clocks. `last_cache_demand_at` moves on any cache demand, including legacy endpoint resolution and runner dispatch; `last_cache_traffic_at` moves only on traffic (managed usage reports with requests, activation-gateway admissions), passed as `Demand.record(id, origin, traffic: true)`. Air inactivity and Air drain cancellation read the traffic clock; every other plan reads demand. An Air service period with no traffic archives as `:idle`, which only traffic returns until `Demand.idle_hold_days/0` passes or the account leaves Air; resolution then neither reports provisioning nor kicks it, and project seeding declines. The Air clock is bounded below by the current service start, so a return by demand alone still gets its full window. Never let a resolution-only path set `traffic: true`, or zero-traffic instances cycle back into service.

- Storage sizing counts `disk_pressure` events as eviction activity to block occupancy shrink, but excludes their bytes from turnover and invalidates all retention ages for the affected account-region-day. Keep snapshots reporting configured ring budgets; runtime pressure caps belong to backfill, not the resize denominator.

- Region location metadata follows the active fleet's physical datacenter:
  production EU-West is OVH Gravelines (`FR-HDF`); the Paris Mac runner cache
  remains `FR-IDF`. Keep physical OTel location separate from stable region IDs,
  pool/storage identifiers, and Route53 latency-region mappings.

- Every managed public host-network region needs a distinct Route53 `aws_region`
  mapping. Stable-enabled retirement requires a supported, fresh stable-ready
  survivor; unsupported destinations must never allow the last advertiser to
  drain. Cover moves and multi-region hand-out when extending the catalog.

- `Identity` separates permanent `accounts.kura_tenant_id` from the current account name. Use the permanent identity for storage, workload names and selectors, peer endpoint hostnames, peer CA lookup and enrollment. Use the current name for client hostnames and authorization grants.
- Account rename changes client hostnames and their manifest revision only after the separate per-account `kura_account_endpoint_migration` flag is enabled (default off in all environments, including already-renamed accounts). While paused, preserve live CR client fields during image/resource applies, fail closed on observation errors, retain published public URLs and emit no redirects; do not guess the live host from the original tenant. Unrenamed accounts still reconcile ordinary template changes. Toggling off freezes deployed routing instead of reverting it. Keep the rendered StatefulSet, peer identity and volume claims unchanged. Retain unexpired historical client hostnames in `clientHostAliases`; `Identity.client_handles/1` filters per-name 90-day deadlines while `Identity.handles/1` preserves identity and attribution for the account lifetime. With migration enabled, deadline expiry changes the manifest revision so the ordinary tick withdraws DNS/ingress/TLS aliases. A pause defers withdrawal without extending deadlines. Publish the new endpoint through existing activation readiness checks; only activated public URLs can be redirect targets. Mesh responses refresh current handle and all authorization aliases even while endpoint migration is paused.
- Keep retired handles reserved in `account_handle_reservations`; telemetry resolves those bindings to the immutable account ID. Signed cache/Bazel analytics use `Projects.projects_by_full_handles/1`, which also resolves reservations; old runtime fallbacks and queued events must remain attributable. Do not resolve an old storage tenant through current account names.
- Production/canary renames for accounts with Kura deployments or self-hosted credentials require the per-account `kura_account_rename` rollout gate. Enable only after the additive CRD/controller and every serving node support the alias protocol. Missing CRD/controller support can remove old routing. The database rename trigger gives the old URL 90 days and clears the new current name's deadline; unrelated renames must not extend earlier deadlines. URL expiry never releases a name reservation.
- See [rollout and migration](../../../../../kura/docs/account-renames.md) and the identity, migration, mesh-controller and usage-controller regression suites.

- `Activation` authenticates wildcard-gateway requests before recording demand or enqueueing immediate provisioning. Resolve only current/unexpired client handles, isolate environments, enforce billing, and return managed regional URLs to avoid proxy loops. The cache backend still authorizes the full artifact request. Trusted managed usage reports refresh active accounts' demand; stale, empty, peer and self-hosted reports do not. See `infra/kura-controller/activation.md`.

- Stable DNS intent is independent of the legacy hand-out flag; never withdraw new clients' derived hostnames when that flag is disabled. Activation selects only fresh stable-ready, non-moving instances in desired regions. Invalid/expired credentials return 401; valid credentials without tenant grants return 403. Signed cache-token origins preserve coarse placement attribution; never trust geo headers relayed by the gateway. Hosted custom/registered endpoints use an explicit CLI override and must not trigger managed provisioning. Self-hosted servers expose one configured main endpoint through `/api/cache/endpoint`.

- Stable routing uses existing instance regions only when an account has no placement rows. Explicit desired/retiring rows take precedence, including an all-retiring set. Keep direct DNS intent, batched reconciliation and activation consistent without writing placement as a read side effect.

- Cold activation polling must continue after the regional deployment closes until stable intent is published and fresh controller readiness reaches the shared projection. Keep this in the bounded unique background worker, never in the authenticated request. Stop for draining, moving, private and unclaimed instances; preserve generation/TLS/provider checks and the original job stall deadline.

- A storage claim is account-wide, but only public regions apply it all or nothing. A private runner-cache region out of room (`:capacity_exhausted`, `:capacity_unplaceable`) keeps its pin while the rest of the account takes the claim; the refusal is still counted, and `ClaimSizing` raises that region to the account claim on a later pass that proposes nothing else. Any other refusal, or a public one, rolls the whole apply back. Every shrink, occupancy included, is floored at the plan's starting claim.
