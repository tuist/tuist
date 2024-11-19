defmodule Tuist.Repo.Migrations.AddIndexToTestCasesProjectId do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:test_cases, [:project_id], concurrently: true)
  end
end
