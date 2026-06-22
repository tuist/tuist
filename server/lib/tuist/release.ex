defmodule Tuist.Release do
  @moduledoc ~S"""
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Ecto.Adapters.SQL
  alias Tuist.Environment

  require Logger

  @app :tuist

  def migrate do
    load_app()

    Logger.info(
      "Migrating with a pool of size of #{:tuist |> Application.get_env(Tuist.Repo) |> Keyword.get(:pool_size)}"
    )

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          check_and_execute_structure_sql(repo)
          Ecto.Migrator.run(repo, :up, all: true)
          grant_runtime_role(repo)
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

  # https://fly.io/phoenix-files/loading-structure-sql-on-prod-without-mix/
  defp check_and_execute_structure_sql(repo) do
    config = repo.config()
    app_name = Keyword.fetch!(config, :otp_app)

    if SQL.table_exists?(repo, "schema_migrations") do
      Logger.info("schema_migrations table already exists")
      :ok
    else
      case repo.__adapter__().structure_load(
             Application.app_dir(app_name, "priv/repo"),
             repo.config()
           ) do
        {:ok, location} = success ->
          Logger.info("The structure for #{inspect(repo)} has been loaded from #{location}")
          success

        {:error, term} when is_binary(term) ->
          Logger.error("The structure for #{inspect(repo)} couldn't be loaded: #{term}")
          {:error, inspect(term)}

        {:error, term} ->
          Logger.error("The structure for #{inspect(repo)} couldn't be loaded: #{inspect(term)}")
          {:error, inspect(term)}
      end
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
    if !Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, role) do
      raise "TUIST_DATABASE_RUNTIME_ROLE must be a valid unquoted PostgreSQL identifier, " <>
              "got: #{inspect(role)}"
    end

    role = quote_identifier(role)
    database = repo.config() |> Keyword.fetch!(:database) |> quote_identifier()

    Enum.each(
      [
        "REVOKE CREATE ON SCHEMA public FROM PUBLIC",
        "REVOKE CREATE ON DATABASE #{database} FROM PUBLIC",
        "GRANT CONNECT ON DATABASE #{database} TO #{role}",
        "GRANT USAGE ON SCHEMA public TO #{role}",
        "REVOKE CREATE ON SCHEMA public FROM #{role}",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{role}",
        "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{role}",
        "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO #{role}",
        "REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.schema_migrations FROM #{role}",
        "GRANT SELECT ON TABLE public.schema_migrations TO #{role}",
        "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{role}",
        "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO #{role}",
        "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO #{role}"
      ],
      &SQL.query!(repo, &1, [])
    )
  end

  defp quote_identifier(identifier) do
    ~s("#{String.replace(to_string(identifier), "\"", "\"\"")}")
  end
end
