defmodule Tuist.IngestRepo.Migration do
  @moduledoc """
  The table engine an ingest migration declares, for the database it runs
  against.

  The in-cluster ClickHouse keeps the analytics tables in a `Replicated`
  database that refuses anything but replicated engines:

      Code: 56. Only tables with a Replicated engine ... are allowed in a
      Replicated database. (UNKNOWN_STORAGE)

  ClickHouse Cloud rewrites a plain `MergeTree` to its own replicated engine on
  the server, but that rewrite is not part of open-source ClickHouse, and the
  development and test databases are not replicated at all. So no single engine
  name is right everywhere, and a migration names the plain engine through
  `engine/1`, which returns the replicated variant only where the database
  requires it:

      create table(:events,
               engine: Migration.engine("ReplacingMergeTree(inserted_at)"),
               options: "ORDER BY (project_id, id)"
             )

      execute("CREATE TABLE events (id UUID) ENGINE = \#{Migration.engine("MergeTree")} ORDER BY id")
  """

  alias Tuist.IngestRepo

  @families ~w(MergeTree ReplacingMergeTree AggregatingMergeTree SummingMergeTree CollapsingMergeTree VersionedCollapsingMergeTree GraphiteMergeTree)

  @doc """
  `engine`, or its replicated variant when the migrated database is `Replicated`.
  """
  def engine(engine, repo \\ IngestRepo) do
    %{rows: [[database_engine]]} =
      repo.query!("SELECT engine FROM system.databases WHERE name = currentDatabase()", [], log: false)

    for_database(engine, database_engine)
  end

  @doc """
  `engine` as a database with the given engine needs it declared.

  Public because the mapping is the part worth testing, and testing it needs no
  replicated database.
  """
  def for_database(engine, "Replicated"), do: replicated(engine)
  def for_database(engine, _database_engine), do: engine

  defp replicated("Replicated" <> _ = engine), do: engine

  defp replicated(engine) do
    family = engine |> String.split("(", parts: 2) |> hd()

    if family in @families do
      "Replicated" <> engine
    else
      raise ArgumentError,
            "#{engine} cannot be created in a Replicated database; use an engine from the MergeTree family"
    end
  end
end
