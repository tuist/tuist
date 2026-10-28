defmodule Atlas.Repo.Migrations.CreateMemoryNodes do
  use Ecto.Migration

  def change do
    create table(:memory_nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :kind, :string, null: false
      add :body, :text, null: false
      add :importance, :float, null: false, default: 0.5
      add :access_count, :integer, null: false, default: 0
      add :last_accessed_at, :utc_datetime
      add :forgotten, :boolean, null: false, default: false

      add :scope, :string, null: false, default: "global"

      add :slack_app, :string

      add :slack_channel_id,
          references(:slack_channels, type: :binary_id, on_delete: :nilify_all)

      add :slack_user_id,
          references(:slack_users, type: :binary_id, on_delete: :nilify_all)

      add :source_slack_message_id,
          references(:slack_messages, type: :binary_id, on_delete: :nilify_all)

      add :embedding_model, :string
      add :embedded_at, :utc_datetime

      timestamps()
    end

    create index(:memory_nodes, [:scope, :forgotten])
    create index(:memory_nodes, [:kind, :forgotten])
    create index(:memory_nodes, [:slack_channel_id])
    create index(:memory_nodes, [:slack_user_id])
    create index(:memory_nodes, [:source_slack_message_id])

    create index(:memory_nodes, ["to_tsvector('english', body)"],
             using: "gin",
             name: :memory_nodes_body_fulltext_index
           )
  end
end
