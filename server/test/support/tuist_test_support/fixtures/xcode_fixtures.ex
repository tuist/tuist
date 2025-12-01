defmodule TuistTestSupport.Fixtures.XcodeFixtures do
  @moduledoc false

  import Ecto.Query
  import TuistTestSupport.Utilities, only: [with_flushed_ingestion_buffers: 1]

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Xcode.XcodeGraph, as: XcodeGraph
  alias Tuist.Xcode.XcodeProject, as: XcodeProject
  alias Tuist.Xcode.XcodeTarget, as: XcodeTarget
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  def xcode_graph_fixture(opts \\ []) do
    with_flushed_ingestion_buffers(fn ->
      command_event_id =
        Keyword.get_lazy(opts, :command_event_id, fn ->
          command_event = CommandEventsFixtures.command_event_fixture()
          command_event.id
        end)

      name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
      id = Keyword.get(opts, :id, UUIDv7.generate())
      binary_build_duration = Keyword.get(opts, :binary_build_duration)
      inserted_at = Keyword.get(opts, :inserted_at, NaiveDateTime.utc_now())

      xcode_graph_data = %{
        id: id,
        name: name,
        command_event_id: command_event_id,
        binary_build_duration: binary_build_duration,
        inserted_at: NaiveDateTime.truncate(inserted_at, :second)
      }

      IngestRepo.insert_all(XcodeGraph, [xcode_graph_data])

      %{
        id: id,
        name: name,
        command_event_id: command_event_id,
        binary_build_duration: binary_build_duration
      }
    end)
  end

  def xcode_project_fixture(opts \\ []) do
    with_flushed_ingestion_buffers(fn ->
      xcode_graph_id =
        Keyword.get_lazy(opts, :xcode_graph_id, fn ->
          xcode_graph_fixture().id
        end)

      command_event_id =
        Keyword.get_lazy(opts, :command_event_id, fn ->
          graph =
            ClickHouseRepo.one(from(g in XcodeGraph, where: g.id == ^xcode_graph_id, select: g.command_event_id))

          graph || CommandEventsFixtures.command_event_fixture().id
        end)

      name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
      path = Keyword.get(opts, :path, ".")
      id = Keyword.get(opts, :id, UUIDv7.generate())

      xcode_project_data = %{
        id: id,
        name: name,
        path: path,
        xcode_graph_id: xcode_graph_id,
        command_event_id: command_event_id,
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }

      IngestRepo.insert_all(XcodeProject, [xcode_project_data])

      %{
        id: id,
        name: name,
        path: path,
        xcode_graph_id: xcode_graph_id,
        command_event_id: command_event_id
      }
    end)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def xcode_target_fixture(opts \\ []) do
    with_flushed_ingestion_buffers(fn ->
      xcode_project_id =
        Keyword.get_lazy(opts, :xcode_project_id, fn ->
          xcode_project_fixture().id
        end)

      command_event_id =
        Keyword.get_lazy(opts, :command_event_id, fn ->
          project =
            ClickHouseRepo.one(
              from(p in XcodeProject,
                where: p.id == ^xcode_project_id,
                select: p.command_event_id
              )
            )

          project || CommandEventsFixtures.command_event_fixture().id
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
        command_event_id: command_event_id,
        binary_cache_hash: binary_cache_hash,
        binary_cache_hit: binary_cache_hit,
        selective_testing_hash: selective_testing_hash,
        selective_testing_hit: selective_testing_hit,
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }

      IngestRepo.insert_all(XcodeTarget, [xcode_target_data])

      %{
        id: id,
        name: name,
        xcode_project_id: xcode_project_id,
        command_event_id: command_event_id,
        binary_cache_hash: binary_cache_hash
      }
    end)
  end
end
