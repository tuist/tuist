defmodule Tuist.Repo.Migrations.AddLogoStorageKeyToProjects do
  use Ecto.Migration

  def up do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :logo_storage_key, :string, default: nil
    end
  end

  def down do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :logo_storage_key
    end
  end
end
