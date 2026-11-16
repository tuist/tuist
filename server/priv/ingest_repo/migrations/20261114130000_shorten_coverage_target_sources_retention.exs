defmodule Tuist.IngestRepo.Migrations.ShortenCoverageTargetSourcesRetention do
  @moduledoc """
  A target's hash source is now read to carry from the test map snapshot of
  the run it points to (`Tuist.TestImpactAnalysis.Carry`), which expires 31
  days after the run, so the rows are kept as long instead of with the
  coverage file detail.
  """
  use Ecto.Migration

  alias Tuist.Environment

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE coverage_target_sources MODIFY TTL toDateTime(inserted_at) + INTERVAL 31 DAY"
    )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE coverage_target_sources MODIFY TTL toDateTime(inserted_at) + INTERVAL #{Environment.coverage_retention_days().files} DAY"
    )
  end
end
