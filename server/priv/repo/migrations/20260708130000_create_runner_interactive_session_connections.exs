defmodule Tuist.Repo.Migrations.CreateRunnerInteractiveSessionConnections do
  use Ecto.Migration

  def change do
    create table(:runner_interactive_session_connections) do
      add :interactive_session_id,
          references(:runner_interactive_sessions,
            on_delete: :delete_all,
            name: :runner_interactive_session_connections_session_fkey
          ),
          null: false

      add :connection_id, :string, null: false
      add :connected_at, :timestamptz, null: false
      add :disconnected_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(
             :runner_interactive_session_connections,
             [:interactive_session_id, :connection_id],
             name: :runner_interactive_session_connections_session_connection_index
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(
             :runner_interactive_session_connections,
             [:interactive_session_id, :disconnected_at],
             name: :runner_interactive_session_connections_disconnected_index
           )

    alter table(:runner_interactive_sessions) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :connection_id, :string
    end
  end
end
