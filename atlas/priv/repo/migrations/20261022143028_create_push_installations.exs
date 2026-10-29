defmodule Atlas.Repo.Migrations.CreatePushInstallations do
  use Ecto.Migration

  def change do
    create table(:push_installations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :installation_id, :uuid, null: false
      # Cleared when retired; live rows cascade with their user.
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all)
      add :oauth_client_id, :text, null: false
      add :platform, :text
      add :environment, :text
      add :token, :binary
      add :token_hash, :binary
      add :token_updated_at, :timestamptz
      add :last_registered_at, :timestamptz
      add :retired_at, :timestamptz
      add :retired_reason, :text
      timestamps(type: :timestamptz)
    end

    # Tombstones keep their installation ID so it can never be registered again.
    create unique_index(:push_installations, [:installation_id])

    create unique_index(:push_installations, [:token_hash],
             where: "retired_at IS NULL",
             name: :push_installations_live_token_hash_index
           )

    create index(:push_installations, [:user_id], where: "retired_at IS NULL")
    create index(:push_installations, [:last_registered_at], where: "retired_at IS NULL")
    create index(:push_installations, [:retired_at], where: "retired_at IS NOT NULL")

    create constraint(:push_installations, :live_or_tombstone,
             check: """
             (retired_at IS NULL AND user_id IS NOT NULL AND token IS NOT NULL AND token_hash IS NOT NULL
               AND platform IS NOT NULL AND environment IS NOT NULL AND token_updated_at IS NOT NULL
               AND last_registered_at IS NOT NULL)
             OR (retired_at IS NOT NULL AND user_id IS NULL AND token IS NULL AND token_hash IS NULL
               AND retired_reason IS NOT NULL)
             """
           )

    create constraint(:push_installations, :supported_platform,
             check: "platform IS NULL OR platform IN ('ios', 'android')"
           )

    create constraint(:push_installations, :supported_environment,
             check: "environment IS NULL OR environment IN ('sandbox', 'production')"
           )

    create constraint(:push_installations, :android_production,
             check: "platform IS DISTINCT FROM 'android' OR environment = 'production'"
           )

    create constraint(:push_installations, :supported_retired_reason,
             check:
               "retired_reason IS NULL OR retired_reason IN ('unregistered', 'owner_changed', 'superseded', 'provider_invalidated', 'session_ended', 'stale', 'evicted')"
           )
  end
end
