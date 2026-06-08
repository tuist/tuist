defmodule Tuist.Repo.Migrations.AddAgentRegistrations do
  use Ecto.Migration

  def change do
    create table(:agent_registrations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :registration_type, :string, null: false
      add :status, :string, null: false
      add :requested_credential_type, :string, null: false
      add :email, :string
      add :claim_token_hash, :binary, null: false
      add :claim_view_token_hash, :binary
      add :otp_hash, :binary
      add :claim_token_expires_at, :timestamptz, null: false
      add :otp_expires_at, :timestamptz
      add :claim_attempt_id, :string
      add :otp_attempt_count, :integer, null: false, default: 0
      add :registration_ip, :string
      add :claim_requested_ip, :string
      add :claim_completed_ip, :string
      add :claimed_at, :timestamptz
      add :claimed_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:agent_registrations, [:claim_token_hash])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:agent_registrations, [:claim_view_token_hash])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:agent_registrations, [:status, :claim_token_expires_at])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:agent_registrations, [:claimed_by_user_id])
  end
end
