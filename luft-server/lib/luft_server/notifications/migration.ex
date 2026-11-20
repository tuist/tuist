defmodule LuftServer.Notifications.Migration do
  @moduledoc "Notification storage migration. Invoke change/0 from the application's next Ecto migration."
  use Ecto.Migration

  def change do
    create table(:thread_live_activities, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, :bigint
      add :oauth_grant_id, :uuid
      add :environment, :text
      add :token, :binary
      add :token_hash, :binary
      add :expires_at, :utc_datetime, null: false
      add :last_digest, :binary
      add :last_phase_digest, :binary
      add :last_sent_at, :utc_datetime
      add :working_thread_ids, {:array, :uuid}, null: false, default: []
      add :retired_at, :utc_datetime
      add :retired_reason, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:thread_live_activities, [:token_hash], where: "retired_at IS NULL")
    create index(:thread_live_activities, [:user_id], where: "user_id IS NOT NULL")
    create index(:thread_live_activities, [:retired_at], where: "retired_at IS NOT NULL")

    create table(:thread_live_activity_starters, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, :bigint, null: false
      add :oauth_grant_id, :uuid, null: false
      add :profile_id, :text, null: false
      add :environment, :text, null: false
      add :token, :binary, null: false
      add :token_hash, :binary, null: false
      add :last_start_id, :uuid
      add :last_started_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:thread_live_activity_starters, [:oauth_grant_id])
    create unique_index(:thread_live_activity_starters, [:token_hash])
    create index(:thread_live_activity_starters, [:user_id])
  end
end
