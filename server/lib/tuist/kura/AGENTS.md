# Kura control plane

- `Identity` separates permanent `accounts.kura_tenant_id` from the current account name. Use the permanent identity for storage, workload names and selectors, endpoint hostnames, peer CA lookup and enrollment. Use the current name for authorization grants.
- Account rename must not change the desired workload manifest or its revision. Mesh responses refresh the runtime authorization handle without changing its configured tenant.
- Keep retired handles reserved in `account_handle_reservations`; telemetry resolves those bindings to the immutable account ID. Do not resolve an old storage tenant through current account names.
- Production/canary renames for accounts with Kura deployments or self-hosted credentials require the per-account `kura_account_rename` rollout gate. Enable only after every serving node supports the additive `account_handle` response field.
- See [rollout and migration](../../../../../kura/docs/account-renames.md) and the identity, migration, mesh-controller and usage-controller regression suites.
