defmodule Tuist.Repo.Migrations.CreateBundleSizeApprovers do
  use Ecto.Migration

  def change do
    create table(:bundle_size_approvers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :github_handle, :string, null: false

      timestamps(type: :timestamptz)
    end

    # The table is created empty immediately above, so this cannot block application writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:bundle_size_approvers, [:project_id, :github_handle])
  end
end
