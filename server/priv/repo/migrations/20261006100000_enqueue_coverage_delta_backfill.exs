defmodule Tuist.Repo.Migrations.EnqueueCoverageDeltaBackfill do
  @moduledoc """
  Queues the backfill of the coverage file deltas
  (`Tuist.Tests.Coverage.Workers.DeltaBackfillWorker`), one job per project
  with complete commits, so they are written by the release that ships the
  tables rather than by hand.

  The work itself needs the application (carried coverage is computed in
  Elixir, over PostgreSQL and ClickHouse together), so this only inserts the
  jobs, naming the worker by string. They land on the `coverage_deltas`
  queue, which only that release runs: an older server never fetches them.
  """
  use Ecto.Migration

  import Ecto.Query

  def up, do: enqueue_backfills!(repo())

  def down, do: :ok

  @doc false
  def enqueue_backfills!(repo) do
    now = NaiveDateTime.utc_now()

    jobs =
      from(c in "coverage_commits", where: c.complete, distinct: true, select: c.project_id)
      |> repo.all()
      |> Enum.map(fn project_id ->
        %{
          state: "available",
          queue: "coverage_deltas",
          worker: "Tuist.Tests.Coverage.Workers.DeltaBackfillWorker",
          args: %{project_id: project_id},
          max_attempts: 20,
          inserted_at: now,
          scheduled_at: now
        }
      end)

    repo.insert_all("oban_jobs", jobs)
  end
end
