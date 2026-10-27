defmodule TuistEx.Analytics.CoverageSummary do
  @moduledoc false

  # What Mix's coverage tool prints once a suite finishes, and its threshold,
  # for a `mix tuist.test --cover` run that counts natively and so leaves
  # Mix's tool out. The project's `test_coverage` options mean what they mean
  # to Mix's tool: `summary: false` turns both off, and
  # `summary: [threshold: N]` sets the threshold, 90 unless set.

  @default_threshold 90

  @doc """
  The project's summary options when a run counting natively should print a
  summary: false on a shard, which runs only part of the suite, or when the
  project turned it off.
  """
  def options(shard_index, config \\ Mix.Project.config()) do
    summary = get_in(config, [:test_coverage, :summary])
    summary = if is_nil(summary), do: true, else: summary
    if is_nil(shard_index), do: summary, else: false
  end

  @doc """
  Prints the summary and, below the threshold, makes the run exit with status
  3 once it is done, as Mix's tool does.
  """
  def report(module_lines, summary_opts) do
    if print(module_lines, summary_opts) == :below_threshold,
      do: System.at_exit(fn _ -> exit({:shutdown, 3}) end)

    :ok
  end

  @doc """
  Prints each module's coverage and the total, and whether the total falls
  below the threshold. Returns `:ok` or `:below_threshold`.
  """
  def print(module_lines, summary_opts) do
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
end
