defmodule Tuist.Repo.Migrations.RemoveXcodeTargetFkFromTestCaseRuns do
  use Ecto.Migration

  def up do
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

  def down do
    # excellent_migrations:safety-assured-for-next-line column_renamed
    rename table(:test_case_runs), :xcode_target_id, to: :xcode_target_id_temp

    alter table(:test_case_runs) do
      add :xcode_target_id, references(:xcode_targets, type: :uuid, on_delete: :nothing)
    end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    UPDATE test_case_runs
    SET xcode_target_id = CAST(xcode_target_id_temp AS UUID)
    WHERE xcode_target_id_temp IS NOT NULL
    """

    alter table(:test_case_runs) do
      remove :xcode_target_id_temp
    end
  end
end
