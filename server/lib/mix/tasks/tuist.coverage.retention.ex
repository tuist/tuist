defmodule Mix.Tasks.Tuist.Coverage.Retention do
  @shortdoc "Applies the configured coverage retention"

  @moduledoc """
  Applies the configured coverage retention to the ClickHouse tables.

  The tables get their time-to-live when they are created, from
  `TUIST_COVERAGE_FILE_RETENTION_DAYS` (per-file detail) and
  `TUIST_COVERAGE_RUN_RETENTION_DAYS` (run totals). Changing either variable
  afterwards changes nothing on its own; run this task to alter the tables to
  the values now in effect. It also drops the commits' coverage past its own
  retention (`Tuist.Tests.Coverage.Commits.prune/1`).

      mix tuist.coverage.retention
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  alias Tuist.Tests.Coverage

  def run(_args) do
    Mix.Task.run("app.start")

    for {table, days} <- Coverage.apply_retention() do
      Mix.shell().info("#{table}: rows expire #{days} days after insertion")
    end

    Mix.shell().info("coverage_commits: #{Coverage.Commits.prune()} rows past retention dropped")
  end
end
