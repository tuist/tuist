defmodule Atlas.Repo.Migrations.CreateAccountActionItems do
  use Ecto.Migration

  def change do
    create table(:account_action_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "open"
      add :kind, :string
      add :title, :string, null: false
      add :body, :text
      add :due_at, :utc_datetime
      add :source, :string, null: false
      add :created_by_agent, :string

      add :triggering_event_id,
          references(:account_events, type: :binary_id, on_delete: :nilify_all)

      add :completed_at, :utc_datetime
      add :dismissed_at, :utc_datetime
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create index(:account_action_items, [:account_id, :status])
    create index(:account_action_items, [:account_id, :status, :due_at])
    create index(:account_action_items, [:status])
    create index(:account_action_items, [:triggering_event_id])
  end
end
