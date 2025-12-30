defmodule Tuist.Repo.Migrations.AddVcsConnectionsTable do
  use Ecto.Migration

  def change do
    create table(:vcs_connections, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :provider, :integer, null: false
      add :repository_full_handle, :string, null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)

      add :github_app_installation_id,
          references(:github_app_installations, type: :uuid, on_delete: :delete_all),
          null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:vcs_connections, [:provider, :project_id])
    create index(:vcs_connections, [:repository_full_handle])
  end
end
