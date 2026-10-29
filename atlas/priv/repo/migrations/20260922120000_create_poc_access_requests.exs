defmodule Atlas.Repo.Migrations.CreatePocAccessRequests do
  use Ecto.Migration

  def change do
    create table(:poc_access_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :poc_id, references(:pocs, type: :binary_id, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :requester_ip, :string
      add :requester_user_agent, :string
      add :slack_channel_id, :string
      add :slack_message_ts, :string
      add :verification_token_hash, :string, null: false
      add :verification_expires_at, :timestamptz, null: false
      add :verified_at, :timestamptz
      add :approved_at, :timestamptz
      add :approved_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :denied_at, :timestamptz
      add :denied_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :revoked_at, :timestamptz
      add :revoked_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :expires_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    create index(:poc_access_requests, [:poc_id])
    create index(:poc_access_requests, [:poc_id, :email])
  end
end
