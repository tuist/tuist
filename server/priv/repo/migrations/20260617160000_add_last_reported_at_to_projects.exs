defmodule Tuist.Repo.Migrations.AddLastReportedAtToProjects do
  use Ecto.Migration

  # Records when the last Slack report was sent per project so the report
  # window survives aggressive oban_jobs pruning. The window used to be
  # derived from the last completed ReportWorker row in oban_jobs, which
  # breaks once completed jobs are pruned within hours (reports fire daily,
  # and weekend gaps / single-day schedules span multiple days).
  #
  # Nullable with no backfill: existing projects fall back to the fixed
  # window for their first post-deploy report, then ReportWorker stamps it.
  def change do
    alter table(:projects) do
      add :last_reported_at, :timestamptz
    end
  end
end
