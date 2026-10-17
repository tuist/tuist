defmodule TuistEx.Coverage do
  @moduledoc """
  A Mix coverage tool that counts lines with the runtime's native line
  counters instead of Erlang's `cover`.

      def project do
        [test_coverage: [tool: TuistEx.Coverage]]
      end

  `mix tuist.setup` adds it. Then `mix test --cover` (or `mix tuist.test
  --cover`) recompiles the project's modules and consolidated protocols from
  their debug info with the counters, switches the runtime to them and counts
  with them. Mix's own tool compiles every module for `cover` again on every
  run, which on a large project costs a minute or more. This tool recompiles
  only the modules a compile wrote since the last run, and none in a build
  `mix tuist.test.build --cover` already instrumented.

  With `mix tuist.test --cover`, Tuist reports the coverage with the run
  whichever tool counted it.

  ## Options

  It reads the same `:test_coverage` options as Mix's tool:

    * `:summary` - prints each module's coverage and the total once the
      suite finishes, as Mix's tool does. On by default; `false` turns it
      off. With `[threshold: percentage]` (90 by default), a total below the
      threshold makes `mix test` exit with status 3. A Tuist shard runs only
      part of the suite, so it prints no summary and checks no threshold.

    * `:ignore_modules` - modules, or regular expressions their names match,
      left out of the summary and of what Tuist reports.

    * `:output` - where Mix's tool writes its HTML report. This tool writes
      none and warns when the option is set: export the coverage
      (`--export-coverage`) and run `mix test.coverage` for one.

  ## When Mix's tool counts instead

  The runtime's counters need the JIT, and other machines cannot count
  into them, so Mix's tool (`Mix.Tasks.Test.Coverage`) runs instead, with
  the same options, when:

    * the run exports its coverage, with `--export-coverage` or Mix's test
      partitions, so `mix test.coverage` can read it;
    * `:local_only` is `false`, to count across nodes;
    * the runtime has no JIT, in which case a warning says so.

  On a Tuist shard that falls back, the coverage is exported to
  `cover/shard-<index>.coverdata` unless the run names an export, rather than
  holding part of the suite to the project's threshold.
  """

  alias TuistEx.Analytics.Coverage, as: Counters

  @default_threshold 90

  @doc """
  Starts counting before the application starts and returns the function Mix
  calls once the suite finishes. Mix passes the compile path and the
  project's `:test_coverage` options.
  """
  def start(compile_path, opts) do
    cond do
      opts[:export] ->
        fallback(compile_path, opts)

      opts[:local_only] == false ->
        fallback(compile_path, opts)

      not Counters.native_supported?() ->
        Mix.shell().info(
          "warning: this runtime cannot count coverage natively (it needs the JIT). " <>
            "Mix's coverage tool runs instead."
        )

        fallback(compile_path, opts)

      true ->
        {count, _skipped} =
          Counters.instrument([compile_path, Mix.Project.consolidation_path()])

        if count > 0,
          do: Mix.shell().info("Instrumented #{count} module(s) for native coverage")

        if Counters.enable_native(compile_path) do
          native(opts)
        else
          fallback(compile_path, opts)
        end
    end
  end

  defp native(opts) do
    summary = Keyword.get(opts, :summary, true)
    index = shard_index()
    Application.put_env(:tuist_ex, :native_coverage, true)
    Application.put_env(:tuist_ex, :coverage_summary, summary != false and is_nil(index))
    Application.delete_env(:tuist_ex, :coverage_lines)
    register_formatter()

    if Keyword.has_key?(project_options(), :output) do
      Mix.shell().info(
        "warning: TuistEx.Coverage writes no HTML report, so :output is not used. " <>
          "Run with --export-coverage and then mix test.coverage for one."
      )
    end

    cond do
      summary == false ->
        fn -> :ok end

      index ->
        fn ->
          Mix.shell().info(
            "\nShard #{index} runs part of the suite, so its coverage is neither " <>
              "summarized nor held to the threshold.\n"
          )
        end

      true ->
        fn -> after_suite(summary) end
    end
  end

  # The counts are the ones the formatter read when the suite finished: by
  # the time Mix calls this, Mimic has swapped the modules it copied back,
  # which resets their native counters.
  @doc false
  def after_suite(
        summary,
        below_threshold \\ fn -> System.at_exit(fn _ -> exit({:shutdown, 3}) end) end
      ) do
    lines =
      case Application.fetch_env(:tuist_ex, :coverage_lines) do
        {:ok, lines} ->
          Application.delete_env(:tuist_ex, :coverage_lines)
          lines

        :error ->
          Mix.shell().info(
            "warning: TuistEx.Coverage's formatter did not run, so the modules Mimic copies " <>
              "may count as uncovered. Keep ExUnit's configured formatters when setting your own."
          )

          Counters.module_lines()
      end

    if summary(lines, summary) == :below_threshold, do: below_threshold.()
  end

  defp fallback(compile_path, opts) do
    Application.put_env(:tuist_ex, :native_coverage, false)

    opts =
      case shard_index() do
        nil -> opts
        index -> Keyword.put(opts, :export, opts[:export] || "shard-#{index}")
      end

    Mix.Tasks.Test.Coverage.start(compile_path, opts)
  end

  # Mix passes its own defaults with the project's options; these are the
  # ones the project set.
  defp project_options, do: Mix.Project.config()[:test_coverage] || []

  defp shard_index, do: Application.get_env(:tuist_ex, :analytics_options, [])[:shard_index]

  # The modules Mimic copies have to be compiled for `cover` once the test
  # helper marked them and before any test stubs them, which is when ExUnit
  # starts its formatters.
  defp register_formatter do
    formatters = Application.get_env(:ex_unit, :formatters, [ExUnit.CLIFormatter])

    if __MODULE__.Formatter not in formatters,
      do: Application.put_env(:ex_unit, :formatters, formatters ++ [__MODULE__.Formatter])
  end

  @doc false
  def summary(module_lines, summary_opts) do
    threshold = threshold(summary_opts)

    covered = fn lines -> Enum.count(lines, fn {_line, ran?} -> ran? end) end

    rows =
      module_lines
      |> Enum.map(fn {module, lines} ->
        {percentage(covered.(lines), map_size(lines)), inspect(module)}
      end)
      |> Enum.sort()

    {total_covered, total} =
      Enum.reduce(module_lines, {0, 0}, fn {_module, lines}, {c, t} ->
        {c + covered.(lines), t + map_size(lines)}
      end)

    total = percentage(total_covered, total)
    width = rows |> Enum.map(&String.length(elem(&1, 1))) |> Enum.max(fn -> 0 end) |> max(10)
    separator = "|------------|-#{String.duplicate("-", width)}-|"

    Mix.shell().info("")
    Mix.shell().info("| Percentage | #{String.pad_trailing("Module", width)} |")
    Mix.shell().info(separator)
    Enum.each(rows, &row(&1, threshold, width))
    Mix.shell().info(separator)
    row({total, "Total"}, threshold, width)
    Mix.shell().info("")

    if total < threshold do
      Mix.shell().info("Coverage test failed, threshold not met:\n")
      Mix.shell().info("    Coverage:  #{format(total, 6)}%")
      Mix.shell().info("    Threshold: #{format(threshold, 6)}%")
      Mix.shell().info("")
      :below_threshold
    else
      :ok
    end
  end

  defp threshold(opts) when is_list(opts), do: Keyword.get(opts, :threshold, @default_threshold)
  defp threshold(_opts), do: @default_threshold

  defp percentage(_covered, 0), do: 100.0
  defp percentage(covered, total), do: covered / total * 100

  defp row({percentage, name}, threshold, width) do
    color = if percentage >= threshold, do: :green, else: :red

    Mix.shell().info([
      "| ",
      color,
      format(percentage, 9),
      "%",
      :reset,
      " | ",
      String.pad_trailing(name, width),
      " |"
    ])
  end

  defp format(number, width), do: :io_lib.format("~#{width}.2f", [number / 1])

  defmodule Formatter do
    @moduledoc false

    # Readies the run when ExUnit starts it (see `register_formatter/0`) and
    # reads the counts for the summary when the suite finishes.
    use GenServer

    alias TuistEx.Analytics.Coverage, as: Counters
    alias TuistEx.Analytics.Report

    def init(_opts) do
      if Application.get_env(:tuist_ex, :native_coverage, false) do
        try do
          Counters.prepare_native()
        rescue
          exception ->
            Report.debug(
              "tuist: could not ready native coverage: #{Exception.message(exception)}"
            )
        end
      end

      {:ok, nil}
    end

    def handle_cast({:suite_finished, _times}, state) do
      if Application.get_env(:tuist_ex, :native_coverage, false) and
           Application.get_env(:tuist_ex, :coverage_summary, false),
         do: Application.put_env(:tuist_ex, :coverage_lines, Counters.module_lines())

      {:noreply, state}
    end

    def handle_cast(_message, state), do: {:noreply, state}
  end
end
