defmodule Tuist.Repo.Migrations.CreateRunnerPrepaidNotifications do
  use Ecto.Migration

  def change do
    # Activations must be migrated before their recipient delivery ledger.
    create table(:runner_prepaid_notifications) do
      add :activation_id, references(:runner_prepaid_activations, on_delete: :delete_all),
        null: false

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :threshold, :integer, null: false
      add :usage_cents, :bigint, null: false
      add :budget_cents, :bigint, null: false
      add :delivered_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_prepaid_notifications, [:activation_id, :user_id, :threshold],
             name: :runner_prepaid_notifications_recipient_threshold_index
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_prepaid_notifications, [:account_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_prepaid_notifications, [:user_id])
  end
end
