defmodule Tuist.Release do
  @moduledoc ~S"""
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Ecto.Adapters.SQL
  alias Tuist.Environment

  require Logger

  @app :tuist
  @processor_write_tables ~w(oban_jobs oban_peers)
  @processor_read_tables ~w(accounts projects automation_alerts webhook_endpoints)

  def migrate do
    load_app()

    Logger.info(
      "Migrating with a pool of size of #{:tuist |> Application.get_env(Tuist.Repo) |> Keyword.get(:pool_size)}"
    )

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          ensure_database_schema(repo)
          Ecto.Migrator.run(repo, :up, all: true)
          grant_runtime_role(repo)
          grant_processor_role(repo)
        end)
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

  defp ensure_database_schema(repo) when repo == Tuist.Repo do
    if Environment.default_database_schema?() do
      :ok
    else
      schema = Environment.quote_postgres_identifier(Environment.database_schema())
      SQL.query!(repo, "CREATE SCHEMA IF NOT EXISTS #{schema}", [])
    end
  end

  defp ensure_database_schema(_repo), do: :ok

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
  # exactly what let new tables (`automation_alerts`, `webhook_endpoints`)
  # reach the ingestion path ungranted, raising `42501` mid-run and
  # discarding the job into partial data. Gated on TUIST_DATABASE_PROCESSOR_ROLE,
  # which the chart sets only for managed CNPG migration Jobs, so self-hosted
  # and non-CNPG deployments leave the role untouched.
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
    # band, cannot linger.
    [
      "REVOKE ALL ON ALL TABLES IN SCHEMA #{quoted_schema} FROM #{role}",
      "GRANT CONNECT ON DATABASE #{database} TO #{role}",
      "GRANT USAGE ON SCHEMA #{quoted_schema} TO #{role}",
      "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE #{write_tables} TO #{role}",
      "GRANT USAGE, SELECT ON SEQUENCE #{quoted_schema}.oban_jobs_id_seq TO #{role}",
      "GRANT SELECT ON TABLE #{read_tables} TO #{role}"
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
