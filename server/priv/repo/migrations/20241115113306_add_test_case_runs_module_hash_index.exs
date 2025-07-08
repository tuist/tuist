defmodule Tuist.Repo.Migrations.AddTestCaseRunsModuleHashIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:test_case_runs, [:module_hash], concurrently: true)
  end
end
