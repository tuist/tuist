defmodule Tuist.Repo.Migrations.CreateMigrationCursors do
  use Ecto.Migration

  def change do
    create table(:migration_cursors, primary_key: false) do
      add :key, :string, primary_key: true, null: false
      add :value, :string, null: false

      timestamps(type: :timestamptz, updated_at: :updated_at, inserted_at: :inserted_at)
    end
  end
end
