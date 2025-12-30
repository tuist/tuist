defmodule Tuist.Repo.Migrations.AddTestCaseRunsFlakyOnlyIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:test_case_runs, [:test_case_id, :flaky])
  end
end
