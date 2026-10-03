defmodule TuistWeb.Coverage.ComponentsTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Coverage.Components

  describe "brief_line_ranges/1" do
    test "shows up to two ranges and folds the rest into an ellipsis, with every range for a title" do
      assert Components.brief_line_ranges([{1, 3}, {5, 5}]) == "1–3, 5"
      assert Components.full_line_ranges([{1, 3}, {5, 5}]) == nil
      assert Components.brief_line_ranges([[1, 3], [5, 5], [8, 9]]) == "1–3, 5, …"
      assert Components.full_line_ranges([[1, 3], [5, 5], [8, 9]]) == "1–3, 5, 8–9"
      assert Components.brief_line_ranges(nil) == "—"
    end
  end

  describe "period_trend/1 and count_trend/2" do
    test "always have a change to show once a series has a point" do
      point = &%{coverage: &1, covered_lines: &2}

      assert Components.period_trend([]) == nil
      assert Components.count_trend([], :covered_lines) == nil

      assert Components.period_trend([point.(40.0, 4)]) == 0.0
      assert Components.count_trend([point.(40.0, 4)], :covered_lines) == 0.0

      assert Components.period_trend([point.(40.0, 4), point.(50.0, 5)]) == 10.0
      assert Components.count_trend([point.(40.0, 4), point.(50.0, 5)], :covered_lines) == 25.0
      assert Components.count_trend([point.(0.0, 0), point.(0.0, 0)], :covered_lines) == 0.0
      assert Components.count_trend([point.(0.0, 0), point.(50.0, 5)], :covered_lines) == 100.0
    end
  end
end
