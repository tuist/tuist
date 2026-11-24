# All indexes belong to the new Halls tables created in this transaction, so there are no
# existing readers or writes to block while their indexes are built.
# excellent_migrations:safety-assured-for-this-file index_not_concurrently
defmodule Tuist.Repo.Migrations.CreateHalls do
  use Ecto.Migration

  def change do
    create table(:halls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :kind, :text, null: false
      add :name, :text
      add :topic, :text
      # The sorted member user IDs of a direct conversation, so the same people
      # always reach the same one.
      add :direct_key, :text
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :request_id, :uuid, null: false
      add :last_position, :bigint, null: false, default: 0
      timestamps(type: :timestamptz)
    end

    create unique_index(:halls, [:account_id, :request_id])
    create unique_index(:halls, [:account_id, :name], where: "kind = 'hall'")
    create unique_index(:halls, [:account_id, :direct_key], where: "kind = 'direct'")
    create index(:halls, [:created_by_id])

    create table(:hall_members, primary_key: false) do
      add :hall_id, references(:halls, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :user_id, references(:users, on_delete: :delete_all), primary_key: true
      add :last_read_position, :bigint, null: false, default: 0
      timestamps(type: :timestamptz)
    end

    create index(:hall_members, [:user_id])

    create table(:hall_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :hall_id, references(:halls, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all)
      add :request_id, :uuid, null: false
      add :position, :bigint, null: false
      add :body, :text, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:hall_messages, [:hall_id, :position])
    create unique_index(:hall_messages, [:hall_id, :request_id])
    create index(:hall_messages, [:author_id])
  end
end
