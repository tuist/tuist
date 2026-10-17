defmodule TuistEx.CoverageTest do
  # Reads and writes application settings Mix reads for the whole VM.
  use ExUnit.Case, async: false
  use Mimic

  alias TuistEx.Analytics.Coverage, as: Counters

  setup do
    previous =
      for {app, key} <- [
            tuist_ex: :analytics_options,
            tuist_ex: :native_coverage,
            tuist_ex: :coverage_summary,
            tuist_ex: :coverage_lines,
            ex_unit: :formatters
          ],
          do: {app, key, Application.fetch_env(app, key)}

    on_exit(fn ->
      for {app, key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(app, key, value)
          :error -> Application.delete_env(app, key)
        end
      end
    end)

    Application.delete_env(:tuist_ex, :analytics_options)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  @mix_defaults [output: "cover", tool: TuistEx.Coverage]

  describe "start/2" do
    test "counts natively, instrumenting the build and its consolidated protocols" do
      expect(Counters, :native_supported?, fn -> true end)

      expect(Counters, :instrument, fn [compile_path, consolidated] ->
        assert compile_path == "ebin"
        assert consolidated == Mix.Project.consolidation_path()
        {0, []}
      end)

      expect(Counters, :enable_native, fn "ebin" -> true end)
      reject(&Mix.Tasks.Test.Coverage.start/2)

      after_suite = TuistEx.Coverage.start("ebin", [export: nil] ++ @mix_defaults)

      assert is_function(after_suite, 0)
      assert Application.get_env(:tuist_ex, :native_coverage) == true
      assert TuistEx.Coverage.Formatter in Application.get_env(:ex_unit, :formatters)
    end

    test "hands over to Mix's tool to export, as --export-coverage and partitions do" do
      reject(&Counters.instrument/1)

      expect(Mix.Tasks.Test.Coverage, :start, fn "ebin", opts ->
        assert opts[:export] == "partition-1"
        fn -> :exported end
      end)

      after_suite = TuistEx.Coverage.start("ebin", [export: "partition-1"] ++ @mix_defaults)

      assert after_suite.() == :exported
      assert Application.get_env(:tuist_ex, :native_coverage) == false
    end

    test "hands over to Mix's tool to count across nodes" do
      reject(&Counters.instrument/1)
      expect(Mix.Tasks.Test.Coverage, :start, fn "ebin", _opts -> fn -> :ok end end)

      TuistEx.Coverage.start("ebin", [export: nil, local_only: false] ++ @mix_defaults)
    end

    test "hands over to Mix's tool, with a warning, where the runtime cannot count natively" do
      expect(Counters, :native_supported?, fn -> false end)
      reject(&Counters.instrument/1)
      expect(Mix.Tasks.Test.Coverage, :start, fn "ebin", _opts -> fn -> :ok end end)

      TuistEx.Coverage.start("ebin", [export: nil] ++ @mix_defaults)

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "cannot count coverage natively"
    end

    test "exports a shard's coverage when it hands over, unless the run names an export" do
      Application.put_env(:tuist_ex, :analytics_options, shard_index: 3)
      stub(Counters, :native_supported?, fn -> false end)

      expect(Mix.Tasks.Test.Coverage, :start, 2, fn "ebin", opts ->
        send(self(), {:export, opts[:export]})
        fn -> :ok end
      end)

      TuistEx.Coverage.start("ebin", [export: nil] ++ @mix_defaults)
      TuistEx.Coverage.start("ebin", [export: "mine"] ++ @mix_defaults)

      assert_received {:export, "shard-3"}
      assert_received {:export, "mine"}
    end

    test "summarizes a shard's coverage neither against nor without the threshold" do
      Application.put_env(:tuist_ex, :analytics_options, shard_index: 1)
      stub(Counters, :native_supported?, fn -> true end)
      stub(Counters, :instrument, fn _dirs -> {0, []} end)
      stub(Counters, :enable_native, fn _ebin -> true end)
      reject(&Counters.module_lines/0)

      after_suite = TuistEx.Coverage.start("ebin", [export: nil] ++ @mix_defaults)
      after_suite.()

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "Shard 1 runs part of the suite"
    end
  end

  describe "after_suite/2" do
    test "summarizes the counts the formatter read when the suite finished" do
      # Started before the run counts natively, so it readies nothing here.
      Application.put_env(:tuist_ex, :native_coverage, false)
      {:ok, formatter} = GenServer.start_link(TuistEx.Coverage.Formatter, [])
      allow(Counters, self(), formatter)
      Application.put_env(:tuist_ex, :native_coverage, true)
      Application.put_env(:tuist_ex, :coverage_summary, true)
      # By the time Mix calls the after-suite function, Mimic has swapped its
      # copies back and their counters read as never run.
      stub(Counters, :module_lines, fn -> %{Demo.Copied => %{1 => false, 2 => false}} end)
      expect(Counters, :module_lines, fn -> %{Demo.Copied => %{1 => true, 2 => true}} end)
      GenServer.cast(formatter, {:suite_finished, %{}})
      :sys.get_state(formatter)

      TuistEx.Coverage.after_suite([threshold: 90], fn -> send(self(), :below) end)

      refute_received :below
      assert shell_output() =~ ~r/100\.00%.*Total/
      assert Application.fetch_env(:tuist_ex, :coverage_lines) == :error
    end

    test "holds the run to the threshold" do
      Application.put_env(:tuist_ex, :coverage_lines, %{Demo.Half => %{1 => true, 2 => false}})

      TuistEx.Coverage.after_suite([threshold: 90], fn -> send(self(), :below) end)

      assert_received :below
    end

    test "warns when the formatter never read the counts, and reads them now" do
      Application.delete_env(:tuist_ex, :coverage_lines)
      expect(Counters, :module_lines, fn -> %{Demo.Covered => %{1 => true}} end)

      TuistEx.Coverage.after_suite(true, fn -> send(self(), :below) end)

      refute_received :below
      assert shell_output() =~ "formatter did not run"
    end
  end

  describe "summary/2" do
    @lines %{
      Demo.Covered => %{1 => true, 2 => true},
      Demo.Half => %{1 => true, 2 => false}
    }

    test "prints each module's coverage and the total, as Mix's tool does" do
      assert TuistEx.Coverage.summary(@lines, threshold: 70) == :ok

      output = shell_output()
      assert output =~ "| Percentage | Module"
      assert output =~ ~r/100\.00%.*Demo\.Covered/
      assert output =~ ~r/50\.00%.*Demo\.Half/
      assert output =~ ~r/75\.00%.*Total/
    end

    test "is below the threshold the project sets, 90 unless it sets one" do
      assert TuistEx.Coverage.summary(@lines, threshold: 80) == :below_threshold
      assert shell_output() =~ "Coverage test failed, threshold not met"
      assert TuistEx.Coverage.summary(@lines, threshold: 70) == :ok
      assert TuistEx.Coverage.summary(@lines, true) == :below_threshold
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
