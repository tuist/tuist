defmodule TuistTestSupport.Fixtures.XcodeFixtures do
  @moduledoc false

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Xcode.Clickhouse.XcodeGraph, as: CHXcodeGraph
  alias Tuist.Xcode.Clickhouse.XcodeProject, as: CHXcodeProject
  alias Tuist.Xcode.Clickhouse.XcodeTarget, as: CHXcodeTarget
  alias Tuist.Xcode.Postgres.XcodeGraph, as: PGXcodeGraph
  alias Tuist.Xcode.Postgres.XcodeProject, as: PGXcodeProject
  alias Tuist.Xcode.Postgres.XcodeTarget, as: PGXcodeTarget
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  def xcode_graph_fixture(opts \\ []) do
    if Environment.clickhouse_configured?() do
      clickhouse_xcode_graph_fixture(opts)
    else
      postgres_xcode_graph_fixture(opts)
    end
  end

  def xcode_project_fixture(opts \\ []) do
    if Environment.clickhouse_configured?() do
      clickhouse_xcode_project_fixture(opts)
    else
      postgres_xcode_project_fixture(opts)
    end
  end

  def xcode_target_fixture(opts \\ []) do
    if Environment.clickhouse_configured?() do
      clickhouse_xcode_target_fixture(opts)
    else
      postgres_xcode_target_fixture(opts)
    end
  end

  defp clickhouse_xcode_graph_fixture(opts) do
    command_event_id =
      Keyword.get_lazy(opts, :command_event_id, fn ->
        command_event = CommandEventsFixtures.command_event_fixture()
        command_event.id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    id = Keyword.get(opts, :id, UUIDv7.generate())

    xcode_graph_data = %{
      id: id,
      name: name,
      command_event_id: command_event_id,
      inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }

    ClickHouseRepo.insert_all(CHXcodeGraph, [xcode_graph_data])

    %{id: id, name: name, command_event_id: command_event_id}
  end

  defp clickhouse_xcode_project_fixture(opts) do
    xcode_graph_id =
      Keyword.get_lazy(opts, :xcode_graph_id, fn ->
        xcode_graph_fixture().id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    path = Keyword.get(opts, :path, ".")
    id = Keyword.get(opts, :id, UUIDv7.generate())

    xcode_project_data = %{
      id: id,
      name: name,
      path: path,
      xcode_graph_id: xcode_graph_id,
      inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }

    ClickHouseRepo.insert_all(CHXcodeProject, [xcode_project_data])

    %{id: id, name: name, path: path, xcode_graph_id: xcode_graph_id}
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp clickhouse_xcode_target_fixture(opts) do
    xcode_project_id =
      Keyword.get_lazy(opts, :xcode_project_id, fn ->
        xcode_project_fixture().id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    binary_cache_hash = Keyword.get(opts, :binary_cache_hash, nil)

    binary_cache_hit =
      case Keyword.get(opts, :binary_cache_hit, :miss) do
        :miss -> 0
        :local -> 1
        :remote -> 2
        "miss" -> 0
        "local" -> 1
        "remote" -> 2
        int when is_integer(int) -> int
      end

    selective_testing_hash = Keyword.get(opts, :selective_testing_hash, nil)

    selective_testing_hit =
      case Keyword.get(opts, :selective_testing_hit, :miss) do
        :miss -> 0
        :local -> 1
        :remote -> 2
        "miss" -> 0
        "local" -> 1
        "remote" -> 2
        nil -> 0
        int when is_integer(int) -> int
      end

    id = Keyword.get(opts, :id, UUIDv7.generate())

    xcode_target_data = %{
      id: id,
      name: name,
      xcode_project_id: xcode_project_id,
      binary_cache_hash: binary_cache_hash,
      binary_cache_hit: binary_cache_hit,
      selective_testing_hash: selective_testing_hash,
      selective_testing_hit: selective_testing_hit,
      inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }

    ClickHouseRepo.insert_all(CHXcodeTarget, [xcode_target_data])

    %{id: id, name: name, xcode_project_id: xcode_project_id, binary_cache_hash: binary_cache_hash}
  end

  # Postgres-specific fixture functions
  def postgres_xcode_graph_fixture(opts) do
    command_event_id =
      Keyword.get_lazy(opts, :command_event_id, fn ->
        command_event = CommandEventsFixtures.command_event_fixture()
        command_event.id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")

    changeset =
      PGXcodeGraph.create_changeset(%PGXcodeGraph{}, %{
        name: name,
        command_event_id: command_event_id
      })

    xcode_graph = Repo.insert!(changeset)

    %{id: xcode_graph.id, name: xcode_graph.name, command_event_id: xcode_graph.command_event_id}
  end

  def postgres_xcode_project_fixture(opts) do
    xcode_graph_id =
      Keyword.get_lazy(opts, :xcode_graph_id, fn ->
        xcode_graph_fixture().id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    path = Keyword.get(opts, :path, ".")

    project_data = %{
      id: UUIDv7.generate(),
      name: name,
      path: path,
      xcode_graph_id: xcode_graph_id,
      inserted_at: DateTime.utc_now(:second),
      updated_at: DateTime.utc_now(:second)
    }

    {1, [xcode_project]} = Repo.insert_all(PGXcodeProject, [project_data], returning: true)

    %{
      id: xcode_project.id,
      name: xcode_project.name,
      path: xcode_project.path,
      xcode_graph_id: xcode_project.xcode_graph_id
    }
  end

  def postgres_xcode_target_fixture(opts) do
    xcode_project_id =
      Keyword.get_lazy(opts, :xcode_project_id, fn ->
        xcode_project_fixture().id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    binary_cache_hash = Keyword.get(opts, :binary_cache_hash, nil)
    binary_cache_hit = Keyword.get(opts, :binary_cache_hit, :miss)
    selective_testing_hash = Keyword.get(opts, :selective_testing_hash, nil)
    selective_testing_hit = Keyword.get(opts, :selective_testing_hit, :miss)

    target_data = %{
      id: UUIDv7.generate(),
      name: name,
      xcode_project_id: xcode_project_id,
      binary_cache_hash: binary_cache_hash,
      binary_cache_hit: binary_cache_hit,
      selective_testing_hash: selective_testing_hash,
      selective_testing_hit: selective_testing_hit,
      inserted_at: DateTime.utc_now(:second),
      updated_at: DateTime.utc_now(:second)
    }

    {1, [xcode_target]} = Repo.insert_all(PGXcodeTarget, [target_data], returning: true)

    %{
      id: xcode_target.id,
      name: xcode_target.name,
      xcode_project_id: xcode_target.xcode_project_id,
      binary_cache_hash: xcode_target.binary_cache_hash
    }
  end
end
