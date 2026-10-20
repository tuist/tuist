defmodule Atlas.Repo.Migrations.CreateSpecRevisions do
  use Ecto.Migration

  def change do
    create table(:spec_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :revision, :integer, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :status, :text, null: false
      add :spec_id, references(:specs, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz, updated_at: false)
    end

    create unique_index(:spec_revisions, [:spec_id, :revision])
    create index(:spec_revisions, [:user_id])
  end
end
