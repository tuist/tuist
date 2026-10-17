defmodule TuistWeb.Coverage.ComponentsTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Coverage.Components

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
