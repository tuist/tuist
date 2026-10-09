defmodule Tuist.IngestRepo.Migrations.AddReportActor do
  use Ecto.Migration

  def up do
    for table <- ~w(build_runs gradle_builds mix_builds test_runs test_case_runs command_events) do
      execute("""
      ALTER TABLE #{table}
        ADD COLUMN IF NOT EXISTS actor_account_id Int64 DEFAULT 0,
        ADD COLUMN IF NOT EXISTS claimed_actor_id String DEFAULT '',
        ADD COLUMN IF NOT EXISTS submission_auth LowCardinality(String) DEFAULT ''
      """)
    end
  end

  def down do
    for table <- ~w(build_runs gradle_builds mix_builds test_runs test_case_runs command_events) do
      execute("""
      ALTER TABLE #{table}
        DROP COLUMN IF EXISTS actor_account_id,
        DROP COLUMN IF EXISTS claimed_actor_id,
        DROP COLUMN IF EXISTS submission_auth
      """)
    end
  end
end
