defmodule Tuist.Release do
  @moduledoc ~S"""
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  require Logger

  @app :tuist

  def migrate do
    Logger.info(
      "Migrating with a pool of size of #{:tuist |> Application.get_env(Tuist.Repo) |> Keyword.get(:pool_size)}"
    )

    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &check_and_execute_structure_sql(&1))
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
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

    Application.load(@app)
  end

  # https://fly.io/phoenix-files/loading-structure-sql-on-prod-without-mix/
  defp check_and_execute_structure_sql(repo) do
    config = repo.config()
    app_name = Keyword.fetch!(config, :otp_app)

    if Ecto.Adapters.SQL.table_exists?(repo, "schema_migrations") do
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
end
