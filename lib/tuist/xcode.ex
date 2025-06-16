defmodule Tuist.Xcode do
  @moduledoc """
  Module for interacting with Xcode primitives such as Xcode graphs.
  """

  alias Tuist.Repo
  alias Tuist.Xcode.XcodeGraph
  alias Tuist.Xcode.XcodeProject
  alias Tuist.Xcode.XcodeTarget

  require Logger

  def create_xcode_graph(%{
        command_event: %Tuist.CommandEvents.Event{id: command_event_id},
        xcode_graph: %{name: name, projects: projects} = xcode_graph
      }) do
    {:ok, %{xcode_graph: xcode_graph}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :xcode_graph,
        XcodeGraph.create_changeset(%XcodeGraph{}, %{
          name: name,
          command_event_id: command_event_id,
          binary_build_duration: Map.get(xcode_graph, :binary_build_duration)
        })
      )
      |> Ecto.Multi.insert_all(
        :xcode_projects,
        XcodeProject,
        &build_xcode_projects(projects, &1),
        returning: true
      )
      |> Ecto.Multi.insert_all(:xcode_targets, XcodeTarget, &build_xcode_targets(projects, &1))
      |> Repo.transaction()

    {:ok, xcode_graph}
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
      Enum.map(xcode_project.targets, &xcode_target_changeset(xcode_project.id, &1))
    end)
  end

  defp to_hit_value(value) when value in ["miss", "local", "remote"], do: String.to_atom(value)

  defp to_hit_value(value) do
    Logger.warning("Received unexpected selective testing metadata hit value: #{value}")
    nil
  end

  defp xcode_target_changeset(xcode_project_id, xcode_target) do
    base_changeset = %{
      id: UUIDv7.generate(),
      name: xcode_target["name"],
      xcode_project_id: xcode_project_id,
      inserted_at: DateTime.utc_now(:second),
      updated_at: DateTime.utc_now(:second)
    }

    base_changeset
    |> then(fn changeset ->
      case xcode_target["binary_cache_metadata"] do
        nil ->
          changeset

        metadata ->
          changeset
          |> Map.put(:binary_cache_hash, metadata["hash"])
          |> Map.put(:binary_cache_hit, to_hit_value(metadata["hit"]))
          |> Map.put(:binary_build_duration, metadata["build_duration"])
      end
    end)
    |> then(fn changeset ->
      case xcode_target["selective_testing_metadata"] do
        nil ->
          changeset

        metadata ->
          changeset
          |> Map.put(:selective_testing_hash, metadata["hash"])
          |> Map.put(:selective_testing_hit, String.to_atom(metadata["hit"]))
      end
    end)
  end
end
