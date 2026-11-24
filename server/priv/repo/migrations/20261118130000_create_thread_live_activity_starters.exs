defmodule Tuist.Repo.Migrations.CreateThreadLiveActivityStarters do
  use Ecto.Migration

  # Luft's ActivityKit push-to-start tokens, one per sign-in, and what the last
  # Live Activity push showed of each thread's phase, which decides its priority.
  def change do
    create table(:thread_live_activity_starters, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :oauth_grant_id, :uuid, null: false
      add :profile_id, :string, null: false
      add :environment, :string, null: false
      add :token, :binary, null: false
      add :token_hash, :binary, null: false
      add :last_start_id, :uuid
      add :last_started_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:thread_live_activity_starters, [:oauth_grant_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:thread_live_activity_starters, [:token_hash])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:thread_live_activity_starters, [:user_id])

    alter table(:thread_live_activities) do
      add :last_phase_digest, :binary
    end
  end
end
