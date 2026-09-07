defmodule Tuist.Gradle.ExecutionGraphTest do
  use ExUnit.Case, async: true

  alias Tuist.Gradle.ExecutionGraph

  test "the longest chain accounts for parallel work instead of summing all tasks" do
    graph = graph([node("core", 20), node("feature", 40), node("app", 10, ["core", "feature"])])
    assert ExecutionGraph.analyze(graph) == %{status: "available", duration_ms: 50, node_ids: ["feature", "app"]}
  end

  test "hard ordering and finalizers affect the longest chain" do
    first = "first" |> node(10) |> Map.put(:finalized_by, ["cleanup"])
    second = "second" |> node(20) |> Map.put(:must_run_after, ["first"])
    graph = graph([first, second, node("cleanup", 30)])
    assert ExecutionGraph.analyze(graph).duration_ms == 40
  end

  test "soft ordering does not create a hard constraint" do
    graph = graph([node("a", 10), "b" |> node(20) |> Map.put(:should_run_after, ["a"])])
    assert ExecutionGraph.analyze(graph).duration_ms == 20
  end

  test "transforms participate in the chain" do
    transform = "transform" |> node(30) |> Map.put(:kind, "transform")
    assert ExecutionGraph.analyze(graph([transform, node("compile", 10, ["transform"])])).duration_ms == 40
  end

  test "cycles, missing nodes, partial graphs, and missing timings are unavailable" do
    for invalid <- [
          graph([node("a", 10, ["b"]), node("b", 10, ["a"])]),
          graph([node("a", 10, ["missing"])]),
          graph([node("a", nil)]),
          %{graph([node("a", 10)]) | status: "partial"},
          graph([node("a", 10), node("a", 10)])
        ] do
      assert ExecutionGraph.analyze(invalid) == %{status: "unavailable", duration_ms: nil, node_ids: []}
    end
  end

  test "zero-duration tasks are valid in diamond dependencies" do
    graph = graph([node("a", 0), node("b", 1, ["a"]), node("c", 1, ["a"]), node("d", 1, ["b", "c"])])
    assert ExecutionGraph.analyze(graph).duration_ms == 2
  end

  defp graph(nodes), do: %{status: "complete", nodes: nodes}

  defp node(id, duration, dependencies \\ []),
    do: %{id: id, duration_ms: duration, dependencies: dependencies, kind: "task"}
end
