defmodule Tuist.Xcode.Postgres do
  @moduledoc """
  Postgres-specific implementation for Xcode data handling.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Tuist.CommandEvents.Event
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

  def selective_testing_analytics(run) do
    test_modules =
      Repo.all(
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
      )

    Tuist.Xcode.build_selective_testing_analytics(test_modules)
  end

  def binary_cache_analytics(run) do
    cacheable_targets =
      Repo.all(
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
      )

    Tuist.Xcode.build_binary_cache_analytics(cacheable_targets)
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
