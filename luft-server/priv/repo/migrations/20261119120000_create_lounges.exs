defmodule LuftServer.Repo.Migrations.CreateLounges do
  use Ecto.Migration

  def change do
    create table(:lounges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Identities remain authoritative upstream; these are scalar references.
      add :account_id, :bigint, null: false
      add :kind, :text, null: false
      add :name, :text
      add :topic, :text
      add :direct_key, :text
      add :created_by_id, :bigint
      add :request_id, :uuid, null: false
      add :last_position, :bigint, null: false, default: 0
      timestamps(type: :timestamptz)
    end

    create unique_index(:lounges, [:account_id, :request_id])
    create unique_index(:lounges, [:account_id, :name], where: "kind = 'lounge'")
    create unique_index(:lounges, [:account_id, :direct_key], where: "kind = 'direct'")
    create index(:lounges, [:created_by_id])

    create table(:lounge_members, primary_key: false) do
      add :lounge_id, references(:lounges, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :user_id, :bigint, primary_key: true
      add :last_read_position, :bigint, null: false, default: 0
      timestamps(type: :timestamptz)
    end

    create index(:lounge_members, [:user_id])

    create table(:lounge_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :lounge_id, references(:lounges, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, :bigint
      add :request_id, :uuid, null: false
      add :position, :bigint, null: false
      add :body, :text, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:lounge_messages, [:lounge_id, :position])
    create unique_index(:lounge_messages, [:lounge_id, :request_id])
    create index(:lounge_messages, [:author_id])
  end
end
