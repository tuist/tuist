defmodule Tuist.IngestRepo.Migrations.AddIsNewToTestCaseRuns do
  use Ecto.Migration

  def change do
    alter table(:test_case_runs) do
      add :is_new, :boolean, default: false
    end
  end
end
