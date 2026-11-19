defmodule Tuist.IngestRepo.Migrations.AddCargoReportActor do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE cargo_builds
      ADD COLUMN IF NOT EXISTS actor_account_id Int64 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS claimed_actor_id String DEFAULT '',
      ADD COLUMN IF NOT EXISTS submission_auth LowCardinality(String) DEFAULT ''
    """)
  end

  def down do
    execute("""
    ALTER TABLE cargo_builds
      DROP COLUMN IF EXISTS actor_account_id,
      DROP COLUMN IF EXISTS claimed_actor_id,
      DROP COLUMN IF EXISTS submission_auth
    """)
  end
end
