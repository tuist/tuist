# Restricted operator access

Managed deployments reconcile the ClickHouse role and user used by
`Tuist.OpsClickHouseRepo` before every server rollout:

1. Helm preserves a generated password in the release's `clickhouse-ops`
   Secret.
2. The server migration job connects with the existing ClickHouse migration
   identity and runs `Tuist.Release` reconciliation.
3. Reconciliation rotates the restricted user's password, removes direct
   privileges and unexpected role assignments, resets the managed role's
   privileges, and reapplies the bounded settings and read grants.
4. The web server derives the restricted connection from the existing
   ClickHouse endpoint and the generated username and password.

The role can read the configured Tuist database and the two system metadata
tables used for table discovery. It receives no external source, cluster, file,
dictionary, user-management, or access-management privileges.
Its read-only mode permits the ClickHouse client to set query-format options
without permitting writes or changes to the read-only setting. Database-level
minimum and maximum constraints prevent callers from raising or disabling the
resource limits.

Managed environment values enable this path by default. A deployment fails
before the server rollout if the ClickHouse migration identity cannot manage
users, roles, or grants.

Self-hosted installations leave reconciliation disabled by default. Enable
`server.config.opsClickHouse.enabled` only when the migration identity has the
required access-management privileges. Set
`server.config.opsClickHouse.existingSecret` to use an existing password Secret
instead of the chart-generated one.

## Recovery fallback

`tuist-ops-readonly.sql` mirrors the managed role and user definition for
recovery outside Helm. Run the
[Structured Query Language](https://en.wikipedia.org/wiki/SQL) file with an
administrator connection:

```sh
clickhouse-client \
  --host <host> \
  --secure \
  --multiquery \
  --param_database <database> \
  --param_username tuist_ops \
  --param_password <generated-password> \
  < infra/clickhouse/tuist-ops-readonly.sql
```

After recovery, confirm `SHOW GRANTS FOR tuist_ops` contains only the managed
role assignment. The server refuses to start the operator repository if its
connection string uses the same username as the application ClickHouse
connection.
