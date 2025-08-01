defmodule Tuist.Xcode.Clickhouse do
  @moduledoc """
  Clickhouse-specific implementation for Xcode data handling.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Xcode.Clickhouse.XcodeGraph
  alias Tuist.Xcode.Clickhouse.XcodeProject
  alias Tuist.Xcode.Clickhouse.XcodeTarget

  def create_xcode_graph(%{
        command_event: %{id: command_event_id},
        xcode_graph: %{name: name, projects: projects} = xcode_graph
      }) do
    xcode_graph_id = UUIDv7.generate()
    inserted_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    xcode_graph_data = [
      %{
        id: xcode_graph_id,
        name: name,
        command_event_id: command_event_id,
        binary_build_duration: Map.get(xcode_graph, :binary_build_duration),
        inserted_at: inserted_at
      }
    ]

    projects_data = build_xcode_projects(projects, command_event_id, xcode_graph_id, inserted_at)
    targets_data = build_xcode_targets(projects, projects_data, inserted_at)

    Task.await_many(
      [
        Task.async(fn ->
          IngestRepo.insert_all(XcodeGraph, xcode_graph_data)
        end),
        Task.async(fn -> IngestRepo.insert_all(XcodeProject, projects_data) end),
        Task.async(fn ->
          targets_data
          |> Enum.chunk_every(1000)
          |> Enum.each(&IngestRepo.insert_all(XcodeTarget, &1))
        end)
      ],
      30_000
    )

    xcode_graph = %{id: xcode_graph_id, name: name, command_event_id: command_event_id}
    {:ok, xcode_graph}
  end

  def selective_testing_analytics(run, flop_params \\ %{}) do
    base_query =
      from(xt in XcodeTarget,
        where: xt.command_event_id == ^run.id,
        where: not is_nil(xt.selective_testing_hash),
        select: %{
          id: xt.id,
          name: xt.name,
          selective_testing_hit: xt.selective_testing_hit,
          selective_testing_hash: xt.selective_testing_hash
        }
      )

    {targets, meta} =
      Tuist.ClickHouseFlop.validate_and_run!(base_query, flop_params, for: XcodeTarget)

    test_modules =
      Enum.map(targets, fn target ->
        %{
          name: target.name,
          selective_testing_hit: hit_string_to_atom(target.selective_testing_hit),
          selective_testing_hash: target.selective_testing_hash
        }
      end)

    analytics = %{test_modules: test_modules}
    {analytics, meta}
  end

  def binary_cache_analytics(run, flop_params \\ %{}) do
    base_query =
      from(xt in XcodeTarget,
        where: xt.command_event_id == ^run.id,
        where: not is_nil(xt.binary_cache_hash),
        select: %{
          id: xt.id,
          name: xt.name,
          binary_cache_hit: xt.binary_cache_hit,
          binary_cache_hash: xt.binary_cache_hash
        }
      )

    {targets, meta} =
      Tuist.ClickHouseFlop.validate_and_run!(base_query, flop_params, for: XcodeTarget)

    cacheable_targets =
      Enum.map(targets, fn target ->
        %{
          name: target.name,
          binary_cache_hit: hit_string_to_atom(target.binary_cache_hit),
          binary_cache_hash: target.binary_cache_hash
        }
      end)

    analytics = %{cacheable_targets: cacheable_targets}
    {analytics, meta}
  end

  def selective_testing_counts(run) do
    result =
      ClickHouseRepo.one(
        from(xt in XcodeTarget,
          where: xt.command_event_id == ^run.id,
          where: not is_nil(xt.selective_testing_hash),
          select: %{
            local: fragment("countIf(selective_testing_hit = 'local')"),
            remote: fragment("countIf(selective_testing_hit = 'remote')"),
            miss: fragment("countIf(selective_testing_hit = 'miss')"),
            total: count(xt.id)
          }
        )
      )

    %{
      selective_testing_local_hits_count: result.local || 0,
      selective_testing_remote_hits_count: result.remote || 0,
      selective_testing_misses_count: result.miss || 0,
      total_count: result.total || 0
    }
  end

  def binary_cache_counts(run) do
    result =
      ClickHouseRepo.one(
        from(xt in XcodeTarget,
          where: xt.command_event_id == ^run.id,
          where: not is_nil(xt.binary_cache_hash),
          select: %{
            local: fragment("countIf(binary_cache_hit = 'local')"),
            remote: fragment("countIf(binary_cache_hit = 'remote')"),
            miss: fragment("countIf(binary_cache_hit = 'miss')"),
            total: count(xt.id)
          }
        )
      )

    %{
      binary_cache_local_hits_count: result.local || 0,
      binary_cache_remote_hits_count: result.remote || 0,
      binary_cache_misses_count: result.miss || 0,
      total_count: result.total || 0
    }
  end

  def has_selective_testing_data?(run) do
    ClickHouseRepo.exists?(
      from(xt in XcodeTarget,
        where: xt.command_event_id == ^run.id,
        where: not is_nil(xt.selective_testing_hash)
      )
    )
  end

  def has_binary_cache_data?(run) do
    ClickHouseRepo.exists?(
      from(xt in XcodeTarget,
        where: xt.command_event_id == ^run.id,
        where: not is_nil(xt.binary_cache_hash)
      )
    )
  end

  def xcode_targets_for_command_event(command_event_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)
    offset = Keyword.get(opts, :offset, 0)

    from(xt in XcodeTarget,
      where: xt.command_event_id == ^command_event_id,
      order_by: xt.name,
      limit: ^limit,
      offset: ^offset,
      select: %{
        id: xt.id,
        name: xt.name,
        binary_cache_hash: xt.binary_cache_hash,
        binary_cache_hit: xt.binary_cache_hit,
        binary_build_duration: xt.binary_build_duration,
        selective_testing_hash: xt.selective_testing_hash,
        selective_testing_hit: xt.selective_testing_hit,
        xcode_project_id: xt.xcode_project_id
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.map(&XcodeTarget.normalize_enums/1)
  end

  defp build_xcode_projects(projects, command_event_id, xcode_graph_id, inserted_at) do
    Enum.map(projects, fn project ->
      %{
        id: UUIDv7.generate(),
        command_event_id: command_event_id,
        xcode_graph_id: xcode_graph_id,
        name: project["name"],
        path: project["path"],
        inserted_at: inserted_at
      }
    end)
  end

  defp build_xcode_targets(projects, projects_data, inserted_at) do
    projects
    |> Enum.map(fn project ->
      %{
        project: Enum.find(projects_data, &(&1.name == project["name"])),
        targets: project["targets"]
      }
    end)
    |> Enum.flat_map(fn xcode_project ->
      Enum.map(
        xcode_project.targets,
        &XcodeTarget.changeset(
          xcode_project.project.command_event_id,
          xcode_project.project.id,
          &1,
          inserted_at
        )
      )
    end)
  end

  # Helper function to convert hit string values to atoms
  defp hit_string_to_atom("miss"), do: :miss
  defp hit_string_to_atom("local"), do: :local
  defp hit_string_to_atom("remote"), do: :remote
  defp hit_string_to_atom(_), do: :miss
end
