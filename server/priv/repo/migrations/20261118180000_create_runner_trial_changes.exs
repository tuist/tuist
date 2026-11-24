defmodule Tuist.Repo.Migrations.CreateRunnerTrialChanges do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # No foreign key: the audit outlives account deletion, like account_plan_changes.
    create table(:runner_trial_changes) do
      add :change_id, :uuid, null: false
      add :account_id, :bigint, null: false
      add :request, :map, null: false
      add :principal, :map, null: false
      add :before, :map, null: false
      add :after, :map, null: false
      timestamps(type: :timestamptz, updated_at: false)
    end

    create unique_index(:runner_trial_changes, [:change_id], concurrently: true)
    create index(:runner_trial_changes, [:account_id, :id], concurrently: true)
  end
end
