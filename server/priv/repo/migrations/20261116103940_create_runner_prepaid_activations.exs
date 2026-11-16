defmodule Tuist.Repo.Migrations.CreateRunnerPrepaidActivations do
  use Ecto.Migration

  def change do
    create table(:runner_prepaid_activations) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :change_id, :uuid, null: false
      add :request, :map, null: false
      add :principal, :map, null: false
      add :before, :map, null: false
      add :after, :map
      add :status, :text, null: false, default: "pending"
      add :error, :text
      add :grant_id, :text
      add :subscription_schedule_id, :text
      add :activated_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    # Both indexes are on the new empty table, in its creation transaction.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_prepaid_activations, [:change_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_prepaid_activations, [:account_id, :id])
  end
end
