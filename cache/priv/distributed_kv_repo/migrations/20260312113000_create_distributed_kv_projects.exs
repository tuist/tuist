defmodule Cache.DistributedKV.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :account_handle, :text, primary_key: true
      add :project_handle, :text, primary_key: true
      add :last_cleanup_at, :timestamptz, null: false
      add :cleanup_lease_expires_at, :timestamptz, null: false
      add :updated_at, :timestamptz, null: false
    end

    create index(:projects, [:cleanup_lease_expires_at])
  end
end
