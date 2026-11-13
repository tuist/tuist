defmodule Tuist.Repo.Migrations.CreateAccountPlanChanges do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # No foreign key: the audit outlives account deletion, like runner_concurrency_limit_changes.
    create table(:account_plan_changes) do
      add :change_id, :uuid, null: false
      add :account_id, :bigint, null: false
      add :request, :map, null: false
      add :principal, :map, null: false
      add :before, :map, null: false
      add :after, :map, null: false
      timestamps(type: :timestamptz, updated_at: false)
    end

    create unique_index(:account_plan_changes, [:change_id], concurrently: true)
    create index(:account_plan_changes, [:account_id, :id], concurrently: true)
  end
end
