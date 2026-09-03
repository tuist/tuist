defmodule Tuist.Release do
  @moduledoc ~S"""
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Ecto.Adapters.SQL
  alias Tuist.ClickHouseCapabilities
  alias Tuist.Environment
  alias Tuist.IngestRepo

  require Logger

  @app :tuist
  @processor_write_tables ~w(oban_jobs oban_peers test_case_run_flaky_corrections)
  @processor_read_tables ~w(accounts projects automation_alerts webhook_endpoints)
  @swift_registry_sync_write_tables ~w(oban_jobs oban_peers)

  # Exact column allowlist for the Grafana "Tuist Product Usage" dashboard role.
  # Column-level rather than table-level because every table below sits next to a
  # secret in the same row: table-level SELECT would hand the dashboard's
  # credential — the one we store in Grafana Cloud — `users.encrypted_password`,
  # `users.token`, `projects.token`, `accounts.s3_secret_access_key`, and
  # `organizations.oauth2_encrypted_client_secret`. `users` is the clearest case:
  # the dashboard needs only the signup timestamp.
  #
  # Adding a column to a panel is a deliberate change here, not something a
  # dashboard edit widens silently. Keep in sync with
  # infra/cnpg/tuist-grafana-ro-grants.sql (a test asserts this).
  @grafana_read_columns [
    {"accounts",
     ~w(id name billing_email organization_id current_month_remote_cache_hits_count current_month_remote_cache_hits_count_updated_at)},
    {"bundles", ~w(project_id inserted_at git_ref)},
    {"organizations", ~w(id created_at)},
    {"previews", ~w(project_id inserted_at)},
    {"projects", ~w(id name account_id created_at build_system)},
    {"roles", ~w(id resource_id resource_type)},
    {"subscriptions", ~w(account_id status)},
    {"users", ~w(created_at)},
    {"users_roles", ~w(user_id role_id)}
  ]

  def migrate do
    load_app()

    Logger.info(
      "Migrating with a pool of size of #{:tuist |> Application.get_env(Tuist.Repo) |> Keyword.get(:pool_size)}"
    )

    assert_supported_clickhouse_version()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          ensure_database_schema(repo)
          Ecto.Migrator.run(repo, :up, all: true)
          assert_all_migrations_up(repo)
          grant_runtime_role(repo)
          grant_processor_role(repo)
          grant_swift_registry_sync_role(repo)
          grant_grafana_role(repo)
          reconcile_ops_clickhouse(repo)
        end)
    end

    do_clone_clickhouse_schema()
  end

  @doc """
  Clones the ClickHouse schema from the system of record onto the in-cluster
  ClickHouse named by `TUIST_CLICKHOUSE_BARE_METAL_URL`.

  A no-op when that variable is unset, which is every environment not
  currently migrating. Idempotent, so the deploy hook that calls it can run on
  every release: an already-cloned schema produces a report of zero changes.

  See `Tuist.ClickHouse.SchemaClone` for why the schema is cloned from the
  source rather than produced by replaying the ingest migrations.
  """
  def clone_clickhouse_schema do
    load_app()
    do_clone_clickhouse_schema()
  end

  defp do_clone_clickhouse_schema do
    case Tuist.ClickHouse.SchemaClone.run() do
      {:ok, report} ->
        failed = report.tables.failed ++ report.views.failed

        if failed == [] do
          Logger.info("ClickHouse schema clone succeeded: #{inspect(report)}")
          :ok
        else
          # Loudly, and by failing the deploy, because a partially cloned
          # schema that reported success would surface much later as the
          # backfill failing on a missing table.
          raise "ClickHouse schema clone failed for: #{inspect(failed)}"
        end

      {:error, :no_target_configured} ->
        Logger.info("TUIST_CLICKHOUSE_BARE_METAL_URL is unset; skipping the ClickHouse schema clone")
        :ok

      {:error, {:target_unreachable, reason}} ->
        # Expected on the deploy that first introduces the ClickHouse
        # StatefulSet: this task runs as a pre-upgrade hook, so the workload
        # does not exist yet. Not a deploy failure, and the next deploy
        # clones. A target that stays unreachable shows up as a schema that
        # never gets cloned, which the backfill refuses to run against.
        Logger.warning("In-cluster ClickHouse is not reachable yet; skipping the schema clone (#{reason})")
        :ok

      {:error, reason} ->
        raise "ClickHouse schema clone failed: #{inspect(reason)}"
    end
  end

  @doc """
  Copies existing ClickHouse rows onto the in-cluster server.

  Run explicitly rather than from a deploy hook: it moves the whole dataset,
  it is resumable, and it should be started and watched deliberately rather
  than blocking a release. Safe to re-run; completed chunks are skipped.
  """
  def backfill_clickhouse do
    load_app()

    case Tuist.ClickHouse.Backfill.run() do
      {:ok, report} ->
        Logger.info("ClickHouse backfill finished: #{inspect(report)}")
        :ok

      {:error, reason} ->
        raise "ClickHouse backfill could not start: #{inspect(reason)}"
    end
  end

  @doc """
  Compares the two ClickHouse servers and raises unless every table agrees.

  This is the gate for the backfill and, once dual writes are on, for the
  ongoing parity between the two.
  """
  def check_clickhouse_parity do
    load_app()

    case Tuist.ClickHouse.Parity.compare() do
      {:ok, %{differing: []} = report} ->
        Logger.info("ClickHouse parity holds across #{report.compared} table(s)")
        :ok

      {:ok, report} ->
        raise "ClickHouse parity failed: #{inspect(report.differing)}"

      {:error, reason} ->
        raise "ClickHouse parity could not run: #{inspect(reason)}"
    end
  end

  # A migration that brings the VM down instead of raising (an exit signal from a
  # linked process, say) leaves `Ecto.Migrator.run/3` looking like it succeeded,
  # so the deploy would report success and boot against a half-migrated database.
  # Fail loudly instead of trusting the run's return value.
  defp assert_all_migrations_up(repo) do
    pending =
      repo
      |> Ecto.Migrator.migrations()
      |> Enum.filter(fn {status, _version, _name} -> status == :down end)

    if !Enum.empty?(pending) do
      versions = Enum.map_join(pending, ", ", fn {_status, version, _name} -> version end)

      raise "Migrations are still pending for #{inspect(repo)} after migrating: #{versions}"
    end
  end

  def seed do
    Application.load(@app)

    # Disable the web server and PromEx so seeding doesn't bind ports.
    # This allows running the seed while a dev server is already running.
    endpoint_config = Application.get_env(@app, TuistWeb.Endpoint, [])
    Application.put_env(@app, TuistWeb.Endpoint, Keyword.put(endpoint_config, :server, false))

    promex_config = Application.get_env(@app, Tuist.PromEx, [])
    Application.put_env(@app, Tuist.PromEx, Keyword.put(promex_config, :disabled, true))

    {:ok, _} = Application.ensure_all_started(@app)

    seed_script = Application.app_dir(@app, "priv/repo/seeds.exs")
    Code.eval_file(seed_script)

    # The full app is running (Oban, etc.) so the BEAM won't exit on its own.
    System.halt(0)
  end

  def rollback do
    load_app()
    version = "ROLLBACK_VERSION" |> System.fetch_env!() |> String.to_integer()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to_exclusive: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # We don't need more than a connection to run migrations
    System.put_env("TUIST_DATABASE_POOL_SIZE", "1")
    migration_database_url = use_migration_database_url()

    Application.load(@app)

    configure_migration_database_url(migration_database_url)
  end

  defp use_migration_database_url do
    case Environment.migration_database_url() do
      url when is_binary(url) and url != "" ->
        System.put_env("DATABASE_URL", url)
        url

      _ ->
        nil
    end
  end

  defp configure_migration_database_url(nil), do: :ok

  defp configure_migration_database_url(url) do
    config = Application.fetch_env!(@app, Tuist.Repo)

    # Release migrations run through Ecto.Migrator.with_repo/3, which starts
    # the Repo from application config and does not accept a separate URL.
    # Mutate the loaded Repo config so migrations can use the owner URL even
    # when the runtime DATABASE_URL points at a narrower web role.
    Application.put_env(
      @app,
      Tuist.Repo,
      Keyword.merge(config, Environment.database_config_from_url(url))
    )
  end

  # Ahead of the migration loop rather than inside it: `repos/0` migrates Postgres
  # first, so checking per-repo would only reject a below-floor ClickHouse after
  # Postgres had already migrated.
  defp assert_supported_clickhouse_version do
    if IngestRepo in repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(IngestRepo, &ClickHouseCapabilities.assert_supported_version!/1)
    end
  end

  defp ensure_database_schema(repo) when repo == Tuist.Repo do
    if Environment.default_database_schema?() do
      :ok
    else
      schema = Environment.quote_postgres_identifier(Environment.database_schema())
      SQL.query!(repo, "CREATE SCHEMA IF NOT EXISTS #{schema}", [])
    end
  end

  defp ensure_database_schema(_repo), do: :ok

  defp reconcile_ops_clickhouse(repo) when repo == IngestRepo do
    username = Environment.ops_clickhouse_username()
    password = Environment.ops_clickhouse_password()
    role = Environment.ops_clickhouse_role()

    if Enum.all?([username, password, role], &(is_binary(&1) and &1 != "")) do
      database = repo.config() |> Keyword.fetch!(:database) |> to_string()
      password_hash = :sha256 |> :crypto.hash(password) |> Base.encode16(case: :lower)

      {setup_queries, assignment_queries} =
        database
        |> ops_clickhouse_reconciliation_queries(username, role, password_hash)
        |> Enum.split(-2)

      Enum.each(setup_queries, &run_clickhouse_access_query(repo, &1))
      revoke_unexpected_clickhouse_roles(repo, username, role)
      Enum.each(assignment_queries, &run_clickhouse_access_query(repo, &1))
    end

    :ok
  end

  defp reconcile_ops_clickhouse(_repo), do: :ok

  defp revoke_unexpected_clickhouse_roles(repo, username, expected_role) do
    result =
      repo.query!(
        """
        SELECT granted_role_name
        FROM system.role_grants
        WHERE user_name = {username:String}
          AND granted_role_name != {expected_role:String}
        """,
        %{"username" => username, "expected_role" => expected_role},
        log: false
      )

    Enum.each(result.rows, fn [role] ->
      role = quote_clickhouse_identifier!(role, "granted ClickHouse role")
      username = quote_clickhouse_identifier!(username, "TUIST_OPS_CLICKHOUSE_USERNAME")
      run_clickhouse_access_query(repo, {"REVOKE #{role} FROM #{username}", []})
    end)
  end

  defp run_clickhouse_access_query(repo, {statement, params}) do
    repo.query!(statement, params, log: false)
  end

  @doc false
  def ops_clickhouse_reconciliation_queries(database, username, role, password_hash) do
    database = quote_clickhouse_identifier!(database, "ClickHouse database")
    username = quote_clickhouse_identifier!(username, "TUIST_OPS_CLICKHOUSE_USERNAME")
    role = quote_clickhouse_identifier!(role, "TUIST_OPS_CLICKHOUSE_ROLE")
    password_hash = validate_clickhouse_password_hash!(password_hash)

    # Mode 2 still rejects writes but permits client-supplied query settings.
    # The bounds below prevent callers from raising or disabling resource limits.
    [
      {"CREATE ROLE IF NOT EXISTS #{role}", []},
      {"REVOKE ALL ON *.* FROM #{role}", []},
      {
        """
        ALTER ROLE #{role} SETTINGS
          readonly = 2,
          max_execution_time = 10 MIN 1 MAX 10,
          max_memory_usage = 1073741824 MIN 1 MAX 1073741824,
          max_rows_to_read = 100000000 MIN 1 MAX 100000000,
          max_bytes_to_read = 5000000000 MIN 1 MAX 5000000000,
          max_result_rows = 201 MIN 1 MAX 201,
          max_result_bytes = 5242880 MIN 1 MAX 5242880,
          max_block_size = 201 MIN 1 MAX 201,
          max_threads = 2 MIN 1 MAX 2
        """,
        []
      },
      {"GRANT SELECT ON #{database}.* TO #{role}", []},
      {"GRANT SELECT ON system.tables TO #{role}", []},
      {"GRANT SELECT ON system.columns TO #{role}", []},
      {
        """
        CREATE USER IF NOT EXISTS #{username}
        IDENTIFIED WITH sha256_hash BY '#{password_hash}'
        """,
        []
      },
      {
        """
        ALTER USER #{username}
        IDENTIFIED WITH sha256_hash BY '#{password_hash}'
        """,
        []
      },
      {"REVOKE ALL ON *.* FROM #{username}", []},
      {"GRANT #{role} TO #{username}", []},
      {"ALTER USER #{username} DEFAULT ROLE #{role}", []}
    ]
  end

  defp quote_clickhouse_identifier!(identifier, source) do
    identifier = to_string(identifier)

    if Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, identifier) do
      "`#{identifier}`"
    else
      raise "#{source} must be a valid ClickHouse identifier, got: #{inspect(identifier)}"
    end
  end

  defp validate_clickhouse_password_hash!(password_hash) do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, password_hash) do
      password_hash
    else
      raise "ClickHouse password hash must be a lowercase SHA-256 hash"
    end
  end

  defp grant_runtime_role(repo) when repo == Tuist.Repo do
    case Environment.database_runtime_role() do
      role when is_binary(role) and role != "" ->
        do_grant_runtime_role(repo, role)

      _ ->
        :ok
    end
  end

  defp grant_runtime_role(_repo), do: :ok

  defp do_grant_runtime_role(repo, role) do
    Environment.validate_postgres_identifier!(role, "TUIST_DATABASE_RUNTIME_ROLE")

    role = Environment.quote_postgres_identifier(role)
    database = repo.config() |> Keyword.fetch!(:database) |> Environment.quote_postgres_identifier()
    schema = Environment.database_schema()
    quoted_schema = Environment.quote_postgres_identifier(schema)

    Enum.each(
      [
        "REVOKE CREATE ON SCHEMA #{quoted_schema} FROM PUBLIC",
        "REVOKE CREATE ON DATABASE #{database} FROM PUBLIC",
        "GRANT CONNECT ON DATABASE #{database} TO #{role}",
        "GRANT USAGE ON SCHEMA #{quoted_schema} TO #{role}",
        "REVOKE CREATE ON SCHEMA #{quoted_schema} FROM #{role}",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA #{quoted_schema} TO #{role}",
        "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA #{quoted_schema} TO #{role}",
        grant_execute_on_owned_functions(schema, role),
        "REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE " <>
          "#{quoted_schema}.schema_migrations FROM #{role}",
        "GRANT SELECT ON TABLE #{quoted_schema}.schema_migrations TO #{role}",
        "ALTER DEFAULT PRIVILEGES IN SCHEMA #{quoted_schema} GRANT SELECT, INSERT, UPDATE, DELETE " <>
          "ON TABLES TO #{role}",
        "ALTER DEFAULT PRIVILEGES IN SCHEMA #{quoted_schema} GRANT USAGE, SELECT ON SEQUENCES TO #{role}",
        "ALTER DEFAULT PRIVILEGES IN SCHEMA #{quoted_schema} GRANT EXECUTE ON FUNCTIONS TO #{role}"
      ],
      &SQL.query!(repo, &1, [])
    )
  end

  # The processor role (the macOS xcresult processor and the in-cluster
  # build processor connect as it) runs the Oban ingestion path, which
  # touches a small, explicitly enumerated set of tables. Applying its
  # per-table grants here — as the schema owner, on every migrate — keeps
  # them in lockstep with schema changes instead of drifting behind the
  # manual `infra/cnpg/tuist-processor-grants.sql` runbook. That drift is
  # exactly what let new tables reach the ingestion path ungranted — first
  # `webhook_endpoints` (test_case.created dispatch), then `automation_alerts`
  # (flaky-alert enqueue) one table further down — each raising `42501`
  # mid-run and discarding the job into partial data. Gated on
  # TUIST_DATABASE_PROCESSOR_ROLE, which the chart
  # sets only for managed CNPG migration Jobs, so self-hosted and non-CNPG
  # deployments leave the role untouched.
  defp grant_processor_role(repo) when repo == Tuist.Repo do
    case Environment.database_processor_role() do
      role when is_binary(role) and role != "" ->
        do_grant_processor_role(repo, role)

      _ ->
        :ok
    end
  end

  defp grant_processor_role(_repo), do: :ok

  defp do_grant_processor_role(repo, role) do
    Environment.validate_postgres_identifier!(role, "TUIST_DATABASE_PROCESSOR_ROLE")

    role = Environment.quote_postgres_identifier(role)
    database = repo.config() |> Keyword.fetch!(:database) |> Environment.quote_postgres_identifier()
    quoted_schema = Environment.quote_postgres_identifier(Environment.database_schema())

    {:ok, :ok} =
      repo.transaction(fn ->
        Enum.each(
          processor_role_grant_statements(role, database, quoted_schema),
          &SQL.query!(repo, &1, [])
        )

        :ok
      end)
  end

  @doc false
  def processor_role_grant_statements(role, database, quoted_schema) do
    write_tables = qualify_tables(quoted_schema, @processor_write_tables)
    read_tables = qualify_tables(quoted_schema, @processor_read_tables)

    # Deny by default: strip every table privilege first, then re-grant only
    # the enumerated surface. A table dropped from the list, or granted out of
    # band, cannot linger. `REVOKE … ON ALL TABLES` only warns (never errors)
    # on tables this role can't revoke, and every GRANT targets a table this
    # migration role owns, so none can hit the permission-denied abort a
    # blanket `GRANT … ON ALL` would.
    [
      "REVOKE ALL ON ALL TABLES IN SCHEMA #{quoted_schema} FROM #{role}",
      "GRANT CONNECT ON DATABASE #{database} TO #{role}",
      "GRANT USAGE ON SCHEMA #{quoted_schema} TO #{role}",
      "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE #{write_tables} TO #{role}",
      "GRANT USAGE, SELECT ON SEQUENCE #{quoted_schema}.oban_jobs_id_seq TO #{role}",
      "GRANT SELECT ON TABLE #{read_tables} TO #{role}"
    ]
  end

  # The swift_registry_sync worker (TUIST_MODE=swift_registry_sync) only
  # touches Oban: it consumes :swift_registry_sync and inserts
  # :swift_registry_release jobs, everything else lives in S3. So its grant
  # is a strict subset of the processor's — the Oban tables, no
  # accounts/projects reads. Applied here on every migrate, as the schema
  # owner, so enabling swiftRegistrySync carries its own grants instead of
  # the drift-prone manual `infra/cnpg/tuist-swift-registry-sync-grants.sql`
  # runbook.
  defp grant_swift_registry_sync_role(repo) when repo == Tuist.Repo do
    case Environment.database_swift_registry_sync_role() do
      role when is_binary(role) and role != "" ->
        do_grant_swift_registry_sync_role(repo, role)

      _ ->
        :ok
    end
  end

  defp grant_swift_registry_sync_role(_repo), do: :ok

  defp do_grant_swift_registry_sync_role(repo, role) do
    Environment.validate_postgres_identifier!(role, "TUIST_DATABASE_SWIFT_REGISTRY_SYNC_ROLE")

    role = Environment.quote_postgres_identifier(role)
    database = repo.config() |> Keyword.fetch!(:database) |> Environment.quote_postgres_identifier()
    quoted_schema = Environment.quote_postgres_identifier(Environment.database_schema())

    {:ok, :ok} =
      repo.transaction(fn ->
        Enum.each(
          swift_registry_sync_role_grant_statements(role, database, quoted_schema),
          &SQL.query!(repo, &1, [])
        )

        :ok
      end)
  end

  # Column-level SELECTs for the Grafana dashboard role. Gated on
  # TUIST_DATABASE_GRAFANA_ROLE, which the chart sets only for managed CNPG
  # migration Jobs, so self-hosted and non-CNPG deployments leave the role
  # untouched. Applied on every migrate so the allowlist tracks the schema
  # declaratively rather than drifting behind a manual psql runbook — the
  # `.sql` file is only a bootstrap/restore fallback.
  defp grant_grafana_role(repo) when repo == Tuist.Repo do
    case Environment.database_grafana_role() do
      role when is_binary(role) and role != "" ->
        do_grant_grafana_role(repo, role)

      _ ->
        :ok
    end
  end

  defp grant_grafana_role(_repo), do: :ok

  defp do_grant_grafana_role(repo, role) do
    Environment.validate_postgres_identifier!(role, "TUIST_DATABASE_GRAFANA_ROLE")

    # CloudNativePG creates this role from the Cluster CR, which Helm applies
    # only after this pre-upgrade migration Job. On the deploy that first
    # introduces the role it therefore does not exist yet: skip the grants
    # rather than aborting the migration (which, under --rollback-on-failure,
    # would roll the release back before CNPG ever creates the role). The next
    # migrate, once the role exists, applies them.
    if role_exists?(repo, role) do
      quoted_role = Environment.quote_postgres_identifier(role)
      database = repo.config() |> Keyword.fetch!(:database) |> Environment.quote_postgres_identifier()
      quoted_schema = Environment.quote_postgres_identifier(Environment.database_schema())

      {:ok, :ok} =
        repo.transaction(fn ->
          Enum.each(
            grafana_role_grant_statements(quoted_role, database, quoted_schema),
            &SQL.query!(repo, &1, [])
          )

          :ok
        end)
    else
      Logger.info(
        "Skipping Grafana role grants: role #{inspect(role)} does not exist yet " <>
          "(CloudNativePG creates it after this migration hook)."
      )

      :ok
    end
  end

  defp role_exists?(repo, role) do
    %{rows: rows} = SQL.query!(repo, "SELECT 1 FROM pg_roles WHERE rolname = $1", [role])
    rows != []
  end

  @doc false
  def grafana_role_grant_statements(role, database, quoted_schema) do
    column_grants =
      Enum.map(@grafana_read_columns, fn {table, columns} ->
        "GRANT SELECT (#{Enum.join(columns, ", ")}) ON #{quoted_schema}.#{table} TO #{role}"
      end)

    [
      # Revoking table privileges also drops the column privileges on that table,
      # so this resets the role to zero before re-granting. That makes the
      # allowlist authoritative: dropping a column here actually removes access
      # on the next migrate instead of leaving a stale grant behind.
      "REVOKE ALL ON ALL TABLES IN SCHEMA #{quoted_schema} FROM #{role}",
      "GRANT CONNECT ON DATABASE #{database} TO #{role}",
      "GRANT USAGE ON SCHEMA #{quoted_schema} TO #{role}"
    ] ++
      column_grants ++
      [
        # Unlike pg_read_all_data, a table added by a future migration must not
        # silently become readable by a credential a third party holds.
        "ALTER DEFAULT PRIVILEGES IN SCHEMA #{quoted_schema} REVOKE ALL ON TABLES FROM #{role}"
      ]
  end

  @doc false
  def swift_registry_sync_role_grant_statements(role, database, quoted_schema) do
    write_tables = qualify_tables(quoted_schema, @swift_registry_sync_write_tables)

    [
      "REVOKE ALL ON ALL TABLES IN SCHEMA #{quoted_schema} FROM #{role}",
      "GRANT CONNECT ON DATABASE #{database} TO #{role}",
      "GRANT USAGE ON SCHEMA #{quoted_schema} TO #{role}",
      "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE #{write_tables} TO #{role}",
      "GRANT USAGE, SELECT ON SEQUENCE #{quoted_schema}.oban_jobs_id_seq TO #{role}"
    ]
  end

  defp qualify_tables(quoted_schema, tables) do
    Enum.map_join(tables, ", ", &"#{quoted_schema}.#{&1}")
  end

  # `GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA <schema>` requires the
  # migration role to own every function in the schema, and aborts the
  # whole statement otherwise. The CNPG PgBouncer pooler installs a
  # superuser-owned `user_search` auth function into public, so a blanket
  # grant can fail with `permission denied for function user_search`.
  # Grant only on functions the migration role owns; `ALTER DEFAULT
  # PRIVILEGES` above already covers functions the role creates later.
  defp grant_execute_on_owned_functions(schema, role) do
    """
    DO $tuist_grant$
    DECLARE
      function_signature text;
    BEGIN
      FOR function_signature IN
        SELECT format(
          '%I.%I(%s)', n.nspname, p.proname,
          pg_catalog.pg_get_function_identity_arguments(p.oid)
        )
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = '#{schema}'
          AND p.prokind <> 'p'
          AND p.proowner = current_user::regrole
      LOOP
        EXECUTE 'GRANT EXECUTE ON FUNCTION ' || function_signature || ' TO #{role}';
      END LOOP;
    END
    $tuist_grant$;
    """
  end
end
