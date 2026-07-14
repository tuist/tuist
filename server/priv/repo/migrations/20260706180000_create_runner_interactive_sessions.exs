defmodule Tuist.Repo.Migrations.CreateRunnerInteractiveSessions do
  use Ecto.Migration

  def change do
    create table(:runner_interactive_sessions) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :workflow_job_id, :bigint, null: false
      add :pod_name, :string, null: false
      add :fleet_name, :string, null: false
      add :kind, :string, null: false
      add :state, :string, null: false, default: "requested"
      add :token_hash, :binary, null: false
      add :requested_by_user_id, references(:users, on_delete: :nilify_all)
      add :connected_at, :timestamptz
      add :closed_at, :timestamptz
      add :expires_at, :timestamptz, null: false
      add :last_activity_at, :timestamptz
      add :close_reason, :string

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:runner_interactive_sessions, :runner_interactive_sessions_kind,
             check: "kind IN ('vnc', 'shell')"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:runner_interactive_sessions, :runner_interactive_sessions_state,
             check: "state IN ('requested', 'ready', 'active', 'closed')"
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_interactive_sessions, [:token_hash])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_interactive_sessions, [:pod_name, :state])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_interactive_sessions, [:account_id, :inserted_at])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_interactive_sessions, [:workflow_job_id, :kind],
             where: "closed_at IS NULL",
             name: :runner_interactive_sessions_open_job_kind_index
           )
  end
end
