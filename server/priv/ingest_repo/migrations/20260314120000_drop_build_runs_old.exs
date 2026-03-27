defmodule Tuist.IngestRepo.Migrations.DropBuildRunsOld do
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("DROP TABLE IF EXISTS build_runs_old")
    IngestRepo.query!("DROP TABLE IF EXISTS build_runs_new")
  end

  def down do
    :ok
  end
end
