defmodule Tuist.Repo.Migrations.RemoveXcodeTargetFkFromTestCaseRuns do
  use Ecto.Migration

  def change do
    alter table(:test_case_runs) do
      add :xcode_target_id_temp, :string
    end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    UPDATE test_case_runs
    SET xcode_target_id_temp = CAST(xcode_target_id AS TEXT)
    WHERE xcode_target_id IS NOT NULL
    """

    alter table(:test_case_runs) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :xcode_target_id
    end

    # excellent_migrations:safety-assured-for-next-line column_renamed
    rename table(:test_case_runs), :xcode_target_id_temp, to: :xcode_target_id
  end
end
