defmodule TuistEx.Analytics.CoverageSummaryTest do
  use ExUnit.Case, async: false

  alias TuistEx.Analytics.CoverageSummary

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  @lines %{
    Demo.Covered => %{1 => true, 2 => true},
    Demo.Half => %{1 => true, 2 => false}
  }

  describe "options/2" do
    test "summarizes unless the project turned it off, with the project's threshold" do
      assert CoverageSummary.options(nil, []) == true

      assert CoverageSummary.options(nil, test_coverage: [summary: [threshold: 80]]) == [
               threshold: 80
             ]

      assert CoverageSummary.options(nil, test_coverage: [summary: false]) == false
    end

    test "never summarizes a shard, which runs part of the suite" do
      assert CoverageSummary.options(2, test_coverage: [summary: [threshold: 80]]) == false
    end
  end

  describe "print/2" do
    test "prints each module's coverage and the total, as Mix's tool does" do
      assert CoverageSummary.print(@lines, threshold: 70) == :ok

      output = shell_output()
      assert output =~ "| Percentage | Module"
      assert output =~ ~r/100\.00%.*Demo\.Covered/
      assert output =~ ~r/50\.00%.*Demo\.Half/
      assert output =~ ~r/75\.00%.*Total/
    end

    test "is below the threshold the project sets, 90 unless it sets one" do
      assert CoverageSummary.print(@lines, threshold: 80) == :below_threshold
      assert shell_output() =~ "Coverage test failed, threshold not met"
      assert CoverageSummary.print(@lines, threshold: 70) == :ok
      assert CoverageSummary.print(@lines, true) == :below_threshold
    end
  end

  defp shell_output(acc \\ []) do
    receive do
      {:mix_shell, :info, [message]} -> shell_output([IO.chardata_to_string(message) | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end
end
