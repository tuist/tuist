# The two tables are new, so building their indexes blocks no readers or writers.
# excellent_migrations:safety-assured-for-this-file index_not_concurrently
defmodule Tuist.Repo.Migrations.CreateThreadRunners do
  use Ecto.Migration

  def change do
    # A person's own machine, registered from Tuist Guild, that threads can run on.
    create table(:thread_runners, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :platform, :text, null: false
      # SHA-256 of the runner's secret, which the server returns only once.
      add :token_hash, :binary, null: false
      # What the runner last reported it allows: folders, terminal, display, portals.
      add :capabilities, :map, null: false, default: %{}
      add :last_seen_at, :timestamptz
      add :revoked_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create unique_index(:thread_runners, [:token_hash])
    create index(:thread_runners, [:user_id])

    # One operation a thread asks a runner to perform, durable so that the
    # replica holding the runner's poll and the agents node waiting for the
    # answer need not be the same, and a restart on either loses nothing.
    create table(:thread_runner_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :runner_id, references(:thread_runners, type: :binary_id, on_delete: :delete_all),
        null: false

      add :op, :text, null: false
      add :payload, :map, null: false
      add :status, :text, null: false, default: "pending"
      add :response, :map
      add :claimed_at, :timestamptz
      add :expires_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    create index(:thread_runner_requests, [:runner_id, :status, :inserted_at])
    create index(:thread_runner_requests, [:expires_at])
  end
end
