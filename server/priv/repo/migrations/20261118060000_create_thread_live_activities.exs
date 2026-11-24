defmodule Tuist.Repo.Migrations.CreateThreadLiveActivities do
  use Ecto.Migration

  # Tuist Guild's aggregate Live Activity for a user's working threads. `id` is the
  # app's registration UUID, not Apple's activity ID. Retired rows are tombstones:
  # owner, grant and token cleared, so the ID can never be registered again.
  def change do
    create table(:thread_live_activities, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all)
      add :oauth_grant_id, :uuid
      add :environment, :string
      add :token, :binary
      add :token_hash, :binary
      add :expires_at, :timestamptz, null: false
      # What was last pushed: a digest of the content-state (never the content)
      # and the threads it showed working, which the next push shows finished once.
      add :last_digest, :binary
      add :last_sent_at, :timestamptz
      add :working_thread_ids, {:array, :uuid}, null: false, default: []
      add :retired_at, :timestamptz
      add :retired_reason, :string
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:thread_live_activities, [:token_hash],
             where: "retired_at IS NULL",
             name: :thread_live_activities_live_token_hash_index
           )

    # Not `retired_at IS NULL`: the user-delete cascade filters on user_id alone.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:thread_live_activities, [:user_id], where: "user_id IS NOT NULL")

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:thread_live_activities, [:retired_at], where: "retired_at IS NOT NULL")
  end
end
