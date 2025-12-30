defmodule Tuist.Repo.Migrations.AddTestCaseRunsStatusIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:test_case_runs, [:status], concurrently: true)
  end
end
