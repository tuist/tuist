defmodule Mix.Tasks.Db.Create do
  @moduledoc ~S"""
  This task extends the ecto.create task installing any necessary extensions right after the creation of the datatabase.
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  import Mix.Ecto

  def run(args) do
    Mix.Tasks.Ecto.Create.run(args)

    # We need to start the app to be able to access the repository
    Mix.Task.run("app.start")

    repos = parse_repo(args)

    for repo <- repos do
      ensure_repo(repo, args)

      case repo do
        Tuist.ClickHouseRepo ->
          :ok

        Tuist.IngestRepo ->
          :ok

        Tuist.Repo ->
          {:ok, _} =
            Ecto.Adapters.SQL.query(repo, "CREATE EXTENSION IF NOT EXISTS timescaledb", [])
      end
    end
  end
end
