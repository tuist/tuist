defmodule Tuist.Repo.Migrations.AddFlakyToTestCaseRuns do
  use Ecto.Migration

  def change do
    alter table(:test_case_runs) do
      add :flaky, :boolean, default: false
    end
  end
end
