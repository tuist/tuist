defmodule Tuist.Repo.Migrations.CreateRequestReplayTables do
  use Ecto.Migration

  def change do
    create table(:refresh_token_replays, primary_key: false) do
      add :kind, :string, primary_key: true
      add :token_hash, :binary, primary_key: true
      add :credential_hash, :binary
      add :response, :binary, null: false
      add :expires_at, :timestamptz, null: false

      timestamps(type: :timestamptz, updated_at: false)
    end

    # The tables are created empty in this migration, so their indexes cannot lock live writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:refresh_token_replays, [:expires_at])

    create table(:idempotent_requests, primary_key: false) do
      add :project_id, :bigint, primary_key: true
      add :kind, :string, primary_key: true
      add :request_id, :uuid, primary_key: true
      add :lease_id, :uuid, null: false
      add :claimed_at, :timestamptz, null: false
      add :completed_at, :timestamptz
      add :result, :binary

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:idempotent_requests, [:claimed_at])
  end
end
