defmodule Tuist.IngestRepo.Migrations.AddIsCiToCasEvents do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE cas_events ADD COLUMN IF NOT EXISTS is_ci Bool DEFAULT false"
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE cas_events DROP COLUMN IF EXISTS is_ci"
  end
end
