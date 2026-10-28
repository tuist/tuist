defmodule Tuist.Repo.Migrations.AddTestReportPublishedAtToOnceRuns do
  use Ecto.Migration

  # `once_runs` is introduced by the same unreleased change, so there is no
  # populated table to lock and no concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file column_added_with_default

  def change do
    alter table(:once_runs) do
      # Set once the run's results reach the shared test store. The publish
      # is not a single atomic write, so without this a replayed
      # `RunCompleted` appends a second copy of every test case row: the run
      # row itself dedupes on its derived id, the children do not.
      add :test_report_published_at, :timestamptz
    end
  end
end
