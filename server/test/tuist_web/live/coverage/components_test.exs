defmodule TuistWeb.Coverage.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Coverage.Components

  describe "measured_by_cell/1" do
    test "shows both of two schemes" do
      html = render_component(&Components.measured_by_cell/1, commit: %{schemes: ["App", "Kit"], partial_schemes: []})

      assert html =~ "App"
      assert html =~ "Kit"
      refute html =~ "+"
    end

    test "folds every scheme past the first into a count" do
      html =
        render_component(&Components.measured_by_cell/1,
          commit: %{schemes: ["App", "Kit", "Core"], partial_schemes: ["Core"]}
        )

      assert html =~ "App"
      assert html =~ "+2"
      assert html =~ ~s(title="Kit, Core")
      refute html =~ ">Kit<"
    end
  end

  describe "brief_line_ranges/1" do
    test "shows up to two ranges and folds the rest into an ellipsis, with every range for a title" do
      assert Components.brief_line_ranges([{1, 3}, {5, 5}]) == "1–3, 5"
      assert Components.full_line_ranges([{1, 3}, {5, 5}]) == nil
      assert Components.brief_line_ranges([[1, 3], [5, 5], [8, 9]]) == "1–3, 5, …"
      assert Components.full_line_ranges([[1, 3], [5, 5], [8, 9]]) == "1–3, 5, 8–9"
      assert Components.brief_line_ranges(nil) == "—"
    end
  end

  describe "chart_points/2" do
    defp point(date, coverage), do: %{committed_at: DateTime.new!(date, ~T[12:00:00]), coverage: coverage}

    test "keeps every commit over a month, the last of each week over half a year, and of each month past it" do
      points = [
        point(~D[2026-01-05], 10.0),
        point(~D[2026-01-07], 11.0),
        point(~D[2026-01-13], 12.0),
        point(~D[2026-02-02], 13.0),
        point(~D[2026-02-20], 14.0)
      ]

      month = {~U[2026-01-01 00:00:00Z], ~U[2026-01-31 00:00:00Z]}
      half_year = {~U[2026-01-01 00:00:00Z], ~U[2026-06-30 00:00:00Z]}
      year = {~U[2026-01-01 00:00:00Z], ~U[2026-12-31 00:00:00Z]}

      assert Components.chart_points(points, month) == points
      assert Enum.map(Components.chart_points(points, half_year), & &1.coverage) == [11.0, 12.0, 13.0, 14.0]
      assert Enum.map(Components.chart_points(points, year), & &1.coverage) == [12.0, 14.0]
    end
  end
end
