defmodule Tuist.IngestRepo.Migrations.MakeTestRunsBuildRunIdNullable do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE test_runs MODIFY COLUMN build_run_id Nullable(UUID) SETTINGS mutations_sync = 1"
    )
  end

  def down do
    execute("ALTER TABLE test_runs MODIFY COLUMN build_run_id UUID SETTINGS mutations_sync = 1")
  end
end
