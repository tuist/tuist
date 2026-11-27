defmodule Tuist.Repo.Migrations.CreateRunnerPrepaidTopUps do
  use Ecto.Migration

  def change do
    create table(:runner_prepaid_top_ups) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :activation_id, references(:runner_prepaid_activations, on_delete: :delete_all),
        null: false

      add :change_id, :uuid, null: false
      add :request, :map, null: false
      add :principal, :map, null: false
      add :before, :map, null: false
      add :after, :map
      add :status, :text, null: false, default: "pending"
      add :error, :text
      add :grant_ids, {:array, :text}, null: false, default: []
      timestamps(type: :timestamptz)
    end

    # All indexes are on the new empty table, in its creation transaction.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_prepaid_top_ups, [:change_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_prepaid_top_ups, [:account_id, :id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_prepaid_top_ups, [:activation_id])
  end
end
