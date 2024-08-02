defmodule Tuist.Repo.Migrations.AddTestCaseRunsFlakyIndex do
  use Ecto.Migration

  def change do
    create index(:test_case_runs, [:test_case_id, :module_hash, :status])
  end
end
