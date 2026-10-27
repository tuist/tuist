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

## Grafana access

Grafana Cloud's ClickHouse data source signs in as `tuist_grafana`, with role
`tuist_grafana_readonly`, through the Private Data source Connect (PDC) agent.
The migration job reconciles it the same way as the operator identity, when
`server.config.grafanaClickHouse.enabled` is set:

- The password comes from the `CLICKHOUSE_GRAFANA` item's `password` field in
  the environment's 1Password vault, through the managed external secrets. The
  same value is entered on the Grafana data source. To rotate it, change the
  item, run a deploy, then update the data source.
- The role reads the Tuist database, `system.tables`, `system.columns` and
  `system.query_log`. Queries run read-only, for at most 120 seconds, with at
  most 8 GiB of memory and 8 threads.
- Every replica's query log from the last day is readable through the
  `grafana_query_log` view in the Tuist database. The view runs as `default`,
  so the role needs no `REMOTE` grant. The other replicas run their part of it
  as the role itself, which is why it reads `system.query_log` too. The
  operator role is denied the view.
- The data source connects to the ClickHouse Service's HTTP port, which
  `pdcAgent.permitRemoteOpen` must list.

## Cluster

The managed server defines a `default` cluster holding every replica, as
ClickHouse Cloud does, so `clusterAllReplicas('default', ...)` reads all of
them. Replicas authenticate to each other with the interserver password.
Queries forwarded to another replica run as the user who sent them, who needs
the `REMOTE` grant. A replica added later joins its peers' cluster at their
next restart.

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

## Keeper local storage

For moving the existing Keeper ensemble off Cloud Volumes, follow the
[staged local-storage migration](keeper-local-storage.md). It preserves member
identities and requires two controlled StatefulSet handoffs.
