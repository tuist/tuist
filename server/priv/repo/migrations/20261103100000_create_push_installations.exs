defmodule Tuist.Repo.Migrations.CreatePushInstallations do
  use Ecto.Migration

  def change do
    create table(:push_installations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :installation_id, :uuid, null: false
      # Cleared when retired; live rows cascade with their user.
      add :user_id, references(:users, on_delete: :delete_all)
      add :oauth_grant_id, :uuid
      add :platform, :string
      add :device_name, :string
      add :environment, :string
      add :token, :binary
      add :token_hash, :binary
      add :last_registered_at, :timestamptz
      add :retired_at, :timestamptz
      add :retired_reason, :string
      timestamps(type: :timestamptz)
    end

    # Tombstones keep their installation ID so it can never be registered again.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:push_installations, [:installation_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:push_installations, [:token_hash],
             where: "retired_at IS NULL",
             name: :push_installations_live_token_hash_index
           )

    # Not `retired_at IS NULL`: the user-delete cascade filters on user_id alone.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:push_installations, [:user_id], where: "user_id IS NOT NULL")

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:push_installations, [:last_registered_at], where: "retired_at IS NULL")

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:push_installations, [:retired_at], where: "retired_at IS NOT NULL")

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:push_installations, :live_or_tombstone,
             check: """
             (retired_at IS NULL AND user_id IS NOT NULL AND oauth_grant_id IS NOT NULL
               AND token IS NOT NULL AND token_hash IS NOT NULL AND platform IS NOT NULL AND environment IS NOT NULL
               AND last_registered_at IS NOT NULL)
             OR (retired_at IS NOT NULL AND user_id IS NULL AND oauth_grant_id IS NULL AND token IS NULL
               AND token_hash IS NULL AND retired_reason IS NOT NULL)
             """
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:push_installations, :supported_platform,
             check: "platform IS NULL OR platform IN ('ios', 'android')"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:push_installations, :supported_environment,
             check: "environment IS NULL OR environment IN ('sandbox', 'production')"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:push_installations, :android_production,
             check: "platform IS DISTINCT FROM 'android' OR environment = 'production'"
           )

    # Notification preferences (`Tuist.Notifications`) apply to every delivery
    # channel. A user's own choice per notification kind for an account (their
    # personal account or an organization). A missing row means enabled.
    create table(:notification_account_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :enabled, :boolean, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:notification_account_preferences, [:user_id, :account_id, :kind])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:notification_account_preferences, [:account_id])

    # A user's override for one project, taking precedence over their account
    # choice. A missing row means the project follows its account.
    create table(:notification_project_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :enabled, :boolean, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:notification_project_preferences, [:user_id, :project_id, :kind])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:notification_project_preferences, [:project_id])
  end
end
