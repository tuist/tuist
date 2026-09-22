# Account renames

Kura's configured tenant is a storage identity. Changing it changes hashed object keys, workload names, endpoint hostnames and peer CA selection. An account rename must keep that identity and refresh only the handle used to authorize requests.

The control plane persists `accounts.kura_tenant_id` and reserves current and retired handles in `account_handle_reservations`. Database triggers initialize the identity, prohibit changing it, and enforce reservation ownership even during a rolling server deployment. Reservations last until account deletion. This intentionally prevents another account from claiming a retired handle.

Enrollment returns the permanent `tenant_id` and the current `account_handle`. Managed peer discovery and self-hosted heartbeats also return `account_handle`. New runtimes replace their in-memory authorization handle on a successful response. Missing fields from older servers preserve the last known handle. Storage and replication continue using the configured tenant. HTTP and REAPI authorize the current handle; requests naming the original reserved tenant are checked against the current handle's grants. Intermediate retired names are reserved but are not runtime aliases. Renames propagate at the mesh refresh cadence, so authorization can temporarily fail until the next successful refresh. Signed cache tokens that embed grants for the retired handle must be refreshed to carry current-handle grants; accepting the original tenant as a routing alias does not rewrite signed token claims. Opaque credentials are evaluated for the new authorization target.

## Migration and rollout

1. Audit all non-destroyed `kura_servers.provisioner_node_ref` values against the existing workload tenant, including archived rows. The migration recognizes a frozen set of historical Kubernetes name suffixes and aborts on unknown references, conflicting identities across regions, duplicate permanent identities or reservation collisions. It holds the accounts table lock while backfilling; measure duration on a production-sized snapshot before deployment. Do not bypass an abort by guessing an identity.
2. Audit already-renamed self-hosted-only accounts separately: without a managed server reference the database has no historical tenant evidence and defaults to the current name. Such accounts need an explicitly reviewed backfill before this migration; this PR cannot infer their old on-disk namespace. The same applies to manual tenant overrides and previously reused historical handles.
3. Deploy the migration and control plane. Keep `kura_account_rename` disabled. The new code rejects renames for Kura accounts in production/canary unless this per-account flag is enabled. Old server processes do not know the application gate, so avoid renames until the server rollout completes.
4. Deploy compatible Kura binaries to all serving managed and self-hosted nodes. Existing nodes ignore the additive response field, but they cannot authorize the new handle. Verify both peer discovery and a real authenticated cache read before enabling the flag for an account.
5. Rename only after that verification. Check that the entire desired manifest, revision, endpoints, CA lookup and configured tenant stay unchanged, and that cache reads succeed under the current handle after refresh.

For an already-renamed mesh, restoring discovery can unblock a pending StatefulSet rollout. Keep an existing `OnDelete` pause in place until a separate, reviewed recovery validates the standby's data and readiness and authorizes any replacement of the serving pod. This PR does not change a live workload or resume a rollout.

## Rollback

The schema migration is deliberately forward-only. Do not delete reservations, revert the permanent tenant to the current name, or rewrite volumes. Disabling the rename flag stops future renames; it does not undo existing ones. Rolling back to a runtime or server that predates this protocol after a rename reintroduces authorization failures. Recover by restoring compatible code while retaining the bindings. An operator-reviewed account rename back to the original handle is possible because the reservation remains owned by the same account, but must account for all integrations, not just Kura.

## Local regression

Build Kura, then run `KURA_RENAME_TEST_BIN=/absolute/path/to/kura shellspec spec/e2e/account_rename_spec.sh` from `kura/`. The ShellSpec starts a loopback control-plane fixture and a native node in an isolated temporary directory. It stores an object, changes the discovery response, reads the same bytes through the new and original handles without restarting, and rejects another account and project.
