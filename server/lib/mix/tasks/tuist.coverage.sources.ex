defmodule Mix.Tasks.Tuist.Coverage.Sources do
  @shortdoc "Records the test versions and target sources carried coverage reads"

  @moduledoc """
  Records the test versions and target sources of every run still within
  the file retention
  (`Tuist.Tests.Coverage.TestSources.backfill/1`), for every project or the
  one given by id. New runs are recorded as their commits fold, and the
  migration that shipped the indexes queued the ones from before
  (`Tuist.Tests.Coverage.Workers.SourceBackfillWorker`); this runs that
  backfill again.

      mix tuist.coverage.sources
      mix tuist.coverage.sources 42

  A release has no Mix; it runs
  `Tuist.Release.backfill_coverage_sources/1` on a live node instead.
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.MixTasks

  alias Tuist.Tests.Coverage.TestSources

  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [] -> Mix.shell().info("#{TestSources.backfill_all()} projects recorded")
      [id] -> id |> String.to_integer() |> TestSources.backfill()
    end
  end
end
