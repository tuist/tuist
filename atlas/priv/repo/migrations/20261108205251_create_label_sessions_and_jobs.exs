defmodule Atlas.Repo.Migrations.CreateLabelSessionsAndJobs do
  use Ecto.Migration

  def change do
    create table(:label_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :relay_token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :relay, :map
      timestamps(type: :utc_datetime_usec)
    end

    create index(:label_sessions, [:owner_id, :expires_at])

    create table(:label_jobs, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :session_id, references(:label_sessions, type: :uuid, on_delete: :delete_all),
        null: false

      add :action, :string, null: false
      add :state, :string, null: false
      add :data, :map, null: false, default: %{}
      add :png, :binary
      timestamps(type: :utc_datetime_usec)
    end

    create index(:label_jobs, [:session_id])
    create constraint(:label_jobs, :valid_label_action, check: "action IN ('print', 'cut')")

    create constraint(:label_jobs, :valid_label_state,
             check:
               "state IN ('preview-only', 'awaiting-approval', 'queued', 'dispatched', 'sdk-confirmed', 'uncertain')"
           )
  end
end
