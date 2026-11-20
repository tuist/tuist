defmodule LuftServer.Repo.Migrations.BindRunnerCredentials do
  use Ecto.Migration

  def change do
    create table(:thread_runner_credentials, primary_key: false) do
      add :runner_id, references(:thread_runners, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create index(:thread_runner_credentials, [:session_id])
  end
end
