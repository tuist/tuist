defmodule Mix.Tasks.Tuist.Coverage.Deltas do
  @shortdoc "Writes the coverage file deltas of the complete commits still measured"

  @moduledoc """
  Writes the coverage file deltas and targets of every complete commit whose
  runs' rows are still kept (`Tuist.Tests.Coverage.Deltas.backfill/1`), for
  every project or the one given by id. New commits are written as they
  complete, and the migration that created the tables queued the ones from
  before (`Tuist.Tests.Coverage.Workers.DeltaBackfillWorker`); this runs
  that backfill again.

      mix tuist.coverage.deltas
      mix tuist.coverage.deltas 42

  A release has no Mix; it runs `Tuist.Release.backfill_coverage_deltas/1`
  on a live node instead.
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.MixTasks

  alias Tuist.Tests.Coverage.Deltas

  def run(args) do
    Mix.Task.run("app.start")

    counts =
      case args do
        [] ->
          Deltas.backfill_all()

        [id] ->
          %{String.to_integer(id) => id |> String.to_integer() |> Tuist.Projects.get_project_by_id() |> Deltas.backfill()}
      end

    for {id, counts} <- counts do
      Mix.shell().info("Project #{id}: #{counts.written} commits written, #{counts.unavailable} without their runs' rows")
    end
  end
end
