defmodule Tuist.IngestRepo.Migrations.AddReportPinsToCoverageRuns do
  use Ecto.Migration

  # The shard reports a run's totals cover: each shard's index and the
  # `inserted_at` its `coverage_run_files` rows share, every one of them on
  # every replica when the row was written (`Coverage.Workers.TotalsWorker`).
  # Readers take each shard's rows at that `inserted_at` rather than its
  # newest, which a replica may hold before the others do. Arrays default to
  # empty on the rows written before; `Coverage.Workers.PinsBackfillWorker`
  # pins those.
  def change do
    alter table(:coverage_runs) do
      add :report_shards, :"Array(UInt32)"
      add :report_inserted_at, :"Array(DateTime64(6))"
    end
  end
end
