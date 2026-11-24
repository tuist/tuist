defmodule Tuist.IngestRepo.Migrations.DropTestImpactRunTests do
  @moduledoc """
  Drops `test_impact_run_tests`, the tests each impact run selected, now
  `test_impact_run_decisions`' bitmaps. The previous release stopped
  writing it and no release since the snapshot reads has read it, so its
  pods, which keep serving while this runs, don't notice.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  # `SYNC` because on a `Replicated` database a plain DROP is queued.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    # excellent_migrations:safety-assured-for-next-line table_dropped
    IngestRepo.query!("DROP TABLE IF EXISTS test_impact_run_tests SYNC", [], timeout: :infinity)
  end

  def down, do: :ok
end
