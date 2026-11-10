defmodule Tuist.Repo.Migrations.CreateAccountAmpWorkspaceConnections do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:account_amp_workspace_connections) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :workspace_id, :uuid, null: false
      add :project_id, :uuid

      timestamps(type: :timestamptz)
    end

    create unique_index(:account_amp_workspace_connections, [:account_id, :workspace_id],
             concurrently: true
           )

    create index(:account_amp_workspace_connections, [:workspace_id], concurrently: true)
  end
end
