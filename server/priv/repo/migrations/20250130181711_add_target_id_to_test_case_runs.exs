defmodule Tuist.Repo.Migrations.AddTargetIdToTestCaseRuns do
  use Ecto.Migration

  def change do
    alter table(:test_case_runs) do
      add :xcode_target_id, references(:xcode_targets, type: :uuid, on_delete: :nothing)
    end
  end
end
