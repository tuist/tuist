defmodule Atlas.Repo.Migrations.CreateAccountFeatureRequests do
  use Ecto.Migration

  def change do
    create table(:account_feature_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_action_item_id,
          references(:account_action_items, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "open"
      add :title, :string, null: false
      add :body, :text
      add :request_count, :integer, null: false, default: 1
      add :last_requested_at, :utc_datetime
      add :created_by_agent, :string
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create index(:account_feature_requests, [:account_id, :status])
    create index(:account_feature_requests, [:account_id, :last_requested_at])
    create index(:account_feature_requests, [:source_action_item_id])

    alter table(:account_action_items) do
      add :feature_request_id,
          references(:account_feature_requests, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:account_action_items, [:feature_request_id])
  end
end
