defmodule Tuist.Repo.Migrations.AddOnceActionPresentation do
  use Ecto.Migration

  def change do
    alter table(:once_actions) do
      add :display_name, :text
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :source_files, {:array, :text}, default: [], null: false
    end
  end
end
