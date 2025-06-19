defmodule Tuist.Xcode.Clickhouse do
  @moduledoc """
  Clickhouse-specific implementation for Xcode data handling.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Event
  alias Tuist.Xcode.Clickhouse.XcodeGraph
  alias Tuist.Xcode.Clickhouse.XcodeProject
  alias Tuist.Xcode.Clickhouse.XcodeTarget

  def create_xcode_graph(%{
        command_event: %Event{id: command_event_id},
        xcode_graph: %{name: name, projects: projects} = xcode_graph
      }) do
    xcode_graph_id = UUIDv7.generate()

    xcode_graph_data = [
      %{
        id: xcode_graph_id,
        name: name,
        command_event_id: command_event_id,
        binary_build_duration: Map.get(xcode_graph, :binary_build_duration),
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }
    ]

    projects_data = build_xcode_projects(projects, xcode_graph_id)
    targets_data = build_xcode_targets(projects, projects_data)

    ClickHouseRepo.insert_all(XcodeGraph, xcode_graph_data)
    ClickHouseRepo.insert_all(XcodeProject, projects_data)
    ClickHouseRepo.insert_all(XcodeTarget, targets_data)

    xcode_graph = %{id: xcode_graph_id, name: name, command_event_id: command_event_id}
    {:ok, xcode_graph}
  end

  def selective_testing_analytics(run) do
    test_modules =
      from(xt in XcodeTarget,
        join: xp in XcodeProject,
        on: xt.xcode_project_id == xp.id,
        join: xg in XcodeGraph,
        on: xp.xcode_graph_id == xg.id,
        where: xg.command_event_id == ^run.id,
        where: not is_nil(xt.selective_testing_hash),
        select: %{
          name: xt.name,
          selective_testing_hit: xt.selective_testing_hit,
          selective_testing_hash: xt.selective_testing_hash
        }
      )
      |> ClickHouseRepo.all()
      |> Enum.map(fn module ->
        %{module | selective_testing_hit: String.to_atom(module.selective_testing_hit)}
      end)

    Tuist.Xcode.build_selective_testing_analytics(test_modules)
  end

  def binary_cache_analytics(run) do
    cacheable_targets =
      from(xt in XcodeTarget,
        join: xp in XcodeProject,
        on: xt.xcode_project_id == xp.id,
        join: xg in XcodeGraph,
        on: xp.xcode_graph_id == xg.id,
        where: xg.command_event_id == ^run.id,
        where: not is_nil(xt.binary_cache_hash),
        select: %{
          name: xt.name,
          binary_cache_hit: xt.binary_cache_hit,
          binary_cache_hash: xt.binary_cache_hash
        }
      )
      |> ClickHouseRepo.all()
      |> Enum.map(fn target ->
        %{target | binary_cache_hit: String.to_atom(target.binary_cache_hit)}
      end)

    Tuist.Xcode.build_binary_cache_analytics(cacheable_targets)
  end

  def xcode_targets_for_command_event(command_event_id) do
    from(xt in XcodeTarget,
      join: xp in XcodeProject,
      on: xt.xcode_project_id == xp.id,
      join: xg in XcodeGraph,
      on: xp.xcode_graph_id == xg.id,
      where: xg.command_event_id == ^command_event_id,
      order_by: xt.name
    )
    |> ClickHouseRepo.all()
    |> Enum.map(&XcodeTarget.normalize_enums/1)
  end

  def get_xcode_targets_grouped_by_project(command_event_id) do
    from(xt in XcodeTarget,
      join: xp in XcodeProject,
      on: xt.xcode_project_id == xp.id,
      join: xg in XcodeGraph,
      on: xp.xcode_graph_id == xg.id,
      where: xg.command_event_id == ^command_event_id,
      order_by: [xp.id, xt.name],
      select: {xp.id, xt}
    )
    |> ClickHouseRepo.all()
    |> Enum.map(fn {project_id, target} -> {project_id, XcodeTarget.normalize_enums(target)} end)
    |> Enum.group_by(fn {project_id, _target} -> project_id end, fn {_project_id, target} ->
      target
    end)
  end

  defp build_xcode_projects(projects, xcode_graph_id) do
    Enum.map(projects, fn project ->
      %{
        id: UUIDv7.generate(),
        xcode_graph_id: xcode_graph_id,
        name: project["name"],
        path: project["path"],
        inserted_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.truncate(:second)
          |> NaiveDateTime.truncate(:second)
      }
    end)
  end

  defp build_xcode_targets(projects, projects_data) do
    projects
    |> Enum.map(fn project ->
      %{
        project: Enum.find(projects_data, &(&1.name == project["name"])),
        targets: project["targets"]
      }
    end)
    |> Enum.flat_map(fn xcode_project ->
      Enum.map(xcode_project.targets, &XcodeTarget.changeset(xcode_project.project.id, &1))
    end)
  end
end
