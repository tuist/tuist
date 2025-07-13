defmodule Tuist.Repo.Migrations.AddTestCaseRunsModuleHashTestCaseIdIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:test_case_runs, [:module_hash, :test_case_id], concurrently: true)
  end
end
