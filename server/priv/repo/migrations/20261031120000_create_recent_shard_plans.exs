defmodule Tuist.Repo.Migrations.CreateRecentShardPlans do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:recent_shard_plans, primary_key: false) do
      add :plan_id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :reference, :string, null: false
      add :storage_target, :string, null: false, default: ""
      add :inserted_at, :timestamptz, null: false
    end

    create index(:recent_shard_plans, [:project_id, :reference, :inserted_at], concurrently: true)
    create index(:recent_shard_plans, [:inserted_at], concurrently: true)
  end
end
