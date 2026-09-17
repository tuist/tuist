defmodule Mix.Tasks.Tuist.Coverage.RecomputeTotals do
  @shortdoc "Republishes every project's coverage totals with the current excluded paths"

  @moduledoc """
  Enqueues the republication of every project's coverage totals with the
  excluded paths in effect now (see `Tuist.Tests.Coverage.ExcludedPaths`).

  A project republishes its totals when its own excluded paths change. The
  server's (`TUIST_COVERAGE_EXCLUDED_PATH_GLOBS`, or the defaults a release
  ships) change nothing on their own: run this task afterwards. In a release,
  `Tuist.Release.recompute_coverage_totals/0` does the same.

      mix tuist.coverage.recompute_totals
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  alias Tuist.Tests.Coverage.Workers.RecomputeTotalsWorker

  def run(_args) do
    Mix.Task.run("app.start")

    jobs = RecomputeTotalsWorker.jobs_for_all_projects()
    Oban.insert_all(jobs)
    Mix.shell().info("Enqueued the coverage totals recompute of #{length(jobs)} project(s)")
  end
end
