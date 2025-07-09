defmodule Tuist.Xcode.Postgres do
  @moduledoc """
  Postgres-specific implementation for Xcode data handling.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Tuist.CommandEvents.Postgres.Event
  alias Tuist.Repo
  alias Tuist.Xcode.Postgres.XcodeGraph
  alias Tuist.Xcode.Postgres.XcodeProject
  alias Tuist.Xcode.Postgres.XcodeTarget

  def create_xcode_graph(%{
        command_event: %Event{id: command_event_id},
        xcode_graph: %{name: name, projects: projects} = xcode_graph
      }) do
    {:ok, %{xcode_graph: xcode_graph}} =
      Multi.new()
      |> Multi.insert(
        :xcode_graph,
        XcodeGraph.create_changeset(%XcodeGraph{}, %{
          name: name,
          command_event_id: command_event_id,
          binary_build_duration: Map.get(xcode_graph, :binary_build_duration)
        })
      )
      |> Multi.insert_all(
        :xcode_projects,
        XcodeProject,
        &build_xcode_projects(projects, &1),
        returning: true
      )
      |> Multi.insert_all(:xcode_targets, XcodeTarget, &build_xcode_targets(projects, &1))
      |> Repo.transaction()

    {:ok, xcode_graph}
  end

  def selective_testing_analytics(run, flop_params \\ %{}) do
    base_query =
      from(xt in XcodeTarget,
        join: xp in XcodeProject,
        on: xt.xcode_project_id == xp.id,
        join: xg in XcodeGraph,
        on: xp.xcode_graph_id == xg.id,
        where: xg.command_event_id == ^run.id,
        where: not is_nil(xt.selective_testing_hash)
      )

    {targets, meta} = Flop.validate_and_run!(base_query, flop_params, for: XcodeTarget)

    test_modules =
      Enum.map(targets, fn target ->
        %{
          name: target.name,
          selective_testing_hit: target.selective_testing_hit,
          selective_testing_hash: target.selective_testing_hash
        }
      end)

    analytics = %{test_modules: test_modules}
    {analytics, meta}
  end

  def binary_cache_analytics(run, flop_params \\ %{}) do
    base_query =
      from(xt in XcodeTarget,
        join: xp in XcodeProject,
        on: xt.xcode_project_id == xp.id,
        join: xg in XcodeGraph,
        on: xp.xcode_graph_id == xg.id,
        where: xg.command_event_id == ^run.id,
        where: not is_nil(xt.binary_cache_hash)
      )

    {targets, meta} = Flop.validate_and_run!(base_query, flop_params, for: XcodeTarget)

    cacheable_targets =
      Enum.map(targets, fn target ->
        %{
          name: target.name,
          binary_cache_hit: target.binary_cache_hit,
          binary_cache_hash: target.binary_cache_hash
        }
      end)

    analytics = %{cacheable_targets: cacheable_targets}
    {analytics, meta}
  end

  def selective_testing_counts(run) do
    base_query =
      from(xt in XcodeTarget,
        join: xp in XcodeProject,
        on: xt.xcode_project_id == xp.id,
        join: xg in XcodeGraph,
        on: xp.xcode_graph_id == xg.id,
        where: xg.command_event_id == ^run.id,
        where: not is_nil(xt.selective_testing_hash)
      )

    counts =
      from(xt in subquery(base_query),
        group_by: xt.selective_testing_hit,
        select: {xt.selective_testing_hit, count(xt.id)}
      )
      |> Repo.all()
      |> Map.new()

    total_count = counts |> Map.values() |> Enum.sum()

    %{
      selective_testing_local_hits_count: Map.get(counts, :local, 0),
      selective_testing_remote_hits_count: Map.get(counts, :remote, 0),
      selective_testing_misses_count: Map.get(counts, :miss, 0),
      total_count: total_count
    }
  end

  def binary_cache_counts(run) do
    base_query =
      from(xt in XcodeTarget,
        join: xp in XcodeProject,
        on: xt.xcode_project_id == xp.id,
        join: xg in XcodeGraph,
        on: xp.xcode_graph_id == xg.id,
        where: xg.command_event_id == ^run.id,
        where: not is_nil(xt.binary_cache_hash)
      )

    counts =
      from(xt in subquery(base_query),
        group_by: xt.binary_cache_hit,
        select: {xt.binary_cache_hit, count(xt.id)}
      )
      |> Repo.all()
      |> Map.new()

    total_count = counts |> Map.values() |> Enum.sum()

    %{
      binary_cache_local_hits_count: Map.get(counts, :local, 0),
      binary_cache_remote_hits_count: Map.get(counts, :remote, 0),
      binary_cache_misses_count: Map.get(counts, :miss, 0),
      total_count: total_count
    }
  end

  def has_selective_testing_data?(run) do
    Repo.exists?(
      from(xt in XcodeTarget,
        join: xp in XcodeProject,
        on: xt.xcode_project_id == xp.id,
        join: xg in XcodeGraph,
        on: xp.xcode_graph_id == xg.id,
        where: xg.command_event_id == ^run.id,
        where: not is_nil(xt.selective_testing_hash)
      )
    )
  end

  def has_binary_cache_data?(run) do
    Repo.exists?(
      from(xt in XcodeTarget,
        join: xp in XcodeProject,
        on: xt.xcode_project_id == xp.id,
        join: xg in XcodeGraph,
        on: xp.xcode_graph_id == xg.id,
        where: xg.command_event_id == ^run.id,
        where: not is_nil(xt.binary_cache_hash)
      )
    )
  end

  def xcode_targets_for_command_event(command_event_id) do
    Repo.all(
      from(xt in XcodeTarget,
        join: xp in XcodeProject,
        on: xt.xcode_project_id == xp.id,
        join: xg in XcodeGraph,
        on: xp.xcode_graph_id == xg.id,
        where: xg.command_event_id == ^command_event_id,
        order_by: xt.name
      )
    )
  end

  defp build_xcode_projects(projects, %{xcode_graph: %{id: xcode_graph_id}}) do
    Enum.map(projects, fn project ->
      %{
        id: UUIDv7.generate(),
        xcode_graph_id: xcode_graph_id,
        name: project["name"],
        path: project["path"],
        inserted_at: DateTime.utc_now(:second),
        updated_at: DateTime.utc_now(:second)
      }
    end)
  end

  defp build_xcode_targets(projects, %{xcode_projects: {_, xcode_projects}}) do
    projects
    |> Enum.map(fn project ->
      %{
        id:
          xcode_projects
          |> Enum.find(&(&1.name == project["name"]))
          |> Map.get(:id),
        targets: project["targets"]
      }
    end)
    |> Enum.flat_map(fn xcode_project ->
      Enum.map(xcode_project.targets, &XcodeTarget.changeset(xcode_project.id, &1))
    end)
  end
end
