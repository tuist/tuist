defmodule Tuist.Repo.Migrations.CreateTestCaseRunFlakyCorrections do
  use Ecto.Migration

  def change do
    create table(:test_case_run_flaky_corrections, primary_key: false) do
      add :test_case_run_id, :uuid, primary_key: true
      add :project_id, :bigint, null: false
      add :test_case_id, :uuid, null: false
      add :git_commit_sha, :string, null: false
      add :state, :string, null: false, default: "pending"

      timestamps(type: :timestamptz)
    end

    # The table is created empty immediately above, so validating the constraint cannot scan existing rows.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :test_case_run_flaky_corrections,
             :test_case_run_flaky_corrections_state,
             check: "state IN ('pending', 'applied')"
           )

    # The table is created empty immediately above, so this cannot block application writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(
             :test_case_run_flaky_corrections,
             [:state, :inserted_at, :test_case_run_id],
             name: :test_case_run_flaky_corrections_pending_sweep_index
           )
  end
end
