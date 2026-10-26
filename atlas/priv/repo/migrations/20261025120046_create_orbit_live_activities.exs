defmodule Atlas.Repo.Migrations.CreateOrbitLiveActivities do
  use Ecto.Migration

  def change do
    create table(:orbit_live_activities, primary_key: false) do
      # App-generated registration UUID, not Apple's Activity.id.
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :oauth_client_id, :text, null: false
      add :token, :binary
      add :token_hash, :binary
      add :environment, :text
      add :expires_at, :timestamptz
      add :retired_at, :timestamptz
      add :last_fingerprint, :binary
      add :last_timestamp, :bigint
      add :last_sent_at, :timestamptz
      add :reconciled_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:orbit_live_activities, [:token_hash], where: "token IS NOT NULL")

    create unique_index(:orbit_live_activities, [:user_id, :oauth_client_id],
             where: "retired_at IS NULL"
           )

    create index(:orbit_live_activities, [:reconciled_at, :id], where: "token IS NOT NULL")
    create index(:orbit_live_activities, [:retired_at], where: "retired_at IS NOT NULL")

    create constraint(:orbit_live_activities, :supported_environment,
             check: "environment IS NULL OR environment IN ('sandbox', 'production')"
           )

    create constraint(:orbit_live_activities, :live_registration,
             check: "retired_at IS NOT NULL OR (token IS NOT NULL AND expires_at IS NOT NULL)"
           )
  end
end
