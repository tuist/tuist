defmodule Tuist.Repo.Migrations.CreateBundleSizeApprovals do
  use Ecto.Migration

  def change do
    create table(:bundle_size_approvals, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :bundle_id, :uuid, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :approved_by_handle, :string, null: false
      add :approved_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    # The table is created empty immediately above, so this cannot block application writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:bundle_size_approvals, [:bundle_id])
  end
end
