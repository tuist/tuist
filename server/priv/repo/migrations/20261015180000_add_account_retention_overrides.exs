defmodule Tuist.Repo.Migrations.AddAccountRetentionOverrides do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :artifact_retention_days, :integer
      add :runner_log_retention_days, :integer
    end

    # Both new columns are NULL on existing rows. Skip the table scan while
    # enforcing the constraints on every subsequent insert or update.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:accounts, :accounts_artifact_retention_days_range,
             check: "artifact_retention_days IS NULL OR artifact_retention_days BETWEEN 1 AND 30",
             validate: false
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:accounts, :accounts_runner_log_retention_days_range,
             check:
               "runner_log_retention_days IS NULL OR runner_log_retention_days BETWEEN 1 AND 90",
             validate: false
           )
  end
end
