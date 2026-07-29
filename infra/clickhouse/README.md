# Restricted operator access

`tuist-ops-readonly.sql` provisions the ClickHouse role and user used by
`Tuist.OpsClickHouseRepo`. The role can read the configured Tuist database and
the two system metadata tables used for table discovery. It receives no
external source, cluster, file, dictionary, or access-management privileges.

Run the [Structured Query Language (SQL)](https://en.wikipedia.org/wiki/SQL)
file once for each managed environment with an administrator connection:

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

Then:

1. Store a connection string for that user in the environment's
   `CLICKHOUSE/ops_url` secret field.
2. Set `server.config.opsClickHouse.enabled: true` for that environment.
3. Confirm `SHOW GRANTS FOR tuist_ops` contains only the role assignment from
   this file.

The server refuses to start the operator repository if its connection string
uses the same username as the application ClickHouse connection.
