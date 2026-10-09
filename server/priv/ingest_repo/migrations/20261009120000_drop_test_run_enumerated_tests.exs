defmodule Tuist.IngestRepo.Migrations.DropTestRunEnumeratedTests do
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  # `SYNC` because on a `Replicated` database a plain DROP is queued.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    # excellent_migrations:safety-assured-for-next-line table_dropped
    IngestRepo.query!("DROP TABLE IF EXISTS test_run_enumerated_tests SYNC", [],
      timeout: :infinity
    )
  end

  def down, do: :ok
end
