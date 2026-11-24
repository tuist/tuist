defmodule Symptoms.Evidence.RootsTest do
  use ExUnit.Case, async: true

  alias Symptoms.Evidence.Roots

  defp down(entity, start), do: %{entity: entity, direction: :down, start: start}
  defp up(entity, start), do: %{entity: entity, direction: :up, start: start}

  test "a cycle collapses into one node and one root" do
    edges = [{"tuist-cache", "tuist.dev"}, {"tuist.dev", "tuist-cache"}]
    result = Roots.analyze([down("tuist-cache", 5), down("tuist.dev", 5)], edges)

    cycle = {:cycle, ["tuist-cache", "tuist.dev"]}
    assert result.components == %{"tuist-cache" => cycle, "tuist.dev" => cycle}
    assert result.roots == [cycle]
    assert result.root_of == %{"tuist-cache" => cycle, "tuist.dev" => cycle}
  end

  test "a caller is explained by a callee degraded in the same direction" do
    edges = [{"route", "postgres"}]

    result = Roots.analyze([down("route", 5), down("postgres", 5)], edges)
    assert result.roots == ["postgres"]
    assert result.explained_by == %{"route" => ["postgres"]}
    assert result.root_of["route"] == "postgres"

    # The callee may start one window later...
    assert Roots.analyze([down("route", 5), down("postgres", 6)], edges).roots == ["postgres"]
    # ...but not two.
    assert Roots.analyze([down("route", 5), down("postgres", 7)], edges).roots == ["postgres", "route"]
    # Nor in the other direction.
    assert Roots.analyze([down("route", 5), up("postgres", 5)], edges).roots == ["postgres", "route"]
  end

  test "explanation follows chains to the deepest root" do
    edges = [{"web", "api"}, {"api", "db"}]
    result = Roots.analyze([down("web", 3), down("api", 3), down("db", 2)], edges)

    assert result.roots == ["db"]
    assert result.root_of == %{"web" => "db", "api" => "db", "db" => "db"}
  end

  test "start times may be DateTimes converted to windows" do
    edges = [{"route", "postgres"}]
    at = ~U[2026-11-16 10:00:00Z]

    degraded = [
      %{entity: "route", direction: :down, start: at},
      %{entity: "postgres", direction: :down, start: DateTime.shift(at, minute: 1)}
    ]

    assert Roots.analyze(degraded, edges).roots == ["postgres"]
    assert Roots.analyze(degraded, edges, window_seconds: 30).roots == ["postgres", "route"]
  end

  test "every caller of a shared resource degrading together is a shared cause" do
    edges = [{"a", "postgres"}, {"b", "postgres"}, {"c", "postgres"}]
    result = Roots.analyze([down("a", 10), down("b", 10), down("c", 11)], edges)

    assert [%{key: {:shared_cause, "postgres"}, resource: "postgres", members: ["a", "b", "c"], start: 10}] =
             result.shared_cause

    assert result.root_of == %{
             "a" => {:shared_cause, "postgres"},
             "b" => {:shared_cause, "postgres"},
             "c" => {:shared_cause, "postgres"}
           }
  end

  test "not every caller degrading is not a shared cause" do
    edges = [{"a", "postgres"}, {"b", "postgres"}, {"c", "postgres"}]
    result = Roots.analyze([down("a", 10), down("b", 10)], edges)

    assert result.shared_cause == []
    assert result.roots == ["a", "b"]
  end

  test "several unrelated entities degrading together are a shared cause" do
    result = Roots.analyze([down("x", 3), down("y", 3), down("z", 4), down("far", 9)], [])

    assert [%{key: {:shared_cause, ["x", "y", "z"]}, resource: nil, members: ["x", "y", "z"]}] =
             result.shared_cause

    assert result.root_of["far"] == "far"
    assert result.root_of["x"] == {:shared_cause, ["x", "y", "z"]}
  end
end
