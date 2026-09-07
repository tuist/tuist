defmodule TuistWeb.GradleExecutionComponentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Gradle
  alias Tuist.Gradle.ExecutionGraph
  alias TuistWeb.GradleExecutionComponent

  setup :verify_on_exit!

  test "search and pagination reuse graph analysis and selection, but changing builds invalidates both" do
    nodes =
      Enum.map(1..60, fn id ->
        %{
          id: to_string(id),
          label: ":task#{id}",
          kind: "task",
          build_path: ":",
          project_path: ":",
          dependencies: [],
          duration_ms: 1,
          started_at: nil
        }
      end)

    graph = %{status: "complete", nodes: nodes}
    expect(ExecutionGraph, :decode, 2, fn "graph" -> graph end)
    expect(ExecutionGraph, :analyze, 2, fn ^graph -> %{status: "available", node_ids: ["1"], duration_ms: 1} end)
    expect(Gradle, :list_tasks, 3, fn _build, _opts -> {[], nil} end)
    assigns = %{build: %{id: "first", execution_graph: "graph"}, params: %{"node" => "1"}}
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    {:ok, socket} = GradleExecutionComponent.update(assigns, socket)
    {:ok, socket} = GradleExecutionComponent.update(%{assigns | params: %{"node" => "1", "graph-page" => "2"}}, socket)
    assert socket.assigns.page == 2

    {:ok, socket} =
      GradleExecutionComponent.update(%{assigns | params: %{"node" => "1", "graph-search" => "task60"}}, socket)

    assert [%{id: "60"}] = socket.assigns.rows
    {:ok, socket} = GradleExecutionComponent.update(%{assigns | params: %{"node" => "2"}}, socket)
    assert socket.assigns.selected.id == "2"
    {:ok, socket} = GradleExecutionComponent.update(%{assigns | build: %{id: "second", execution_graph: "graph"}}, socket)
    assert socket.assigns.graph_build_id == "second"
  end
end
