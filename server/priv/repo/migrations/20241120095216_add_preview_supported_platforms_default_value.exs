defmodule Tuist.Repo.Migrations.AddPreviewSupportedPlatformsDefaultValue do
  use Ecto.Migration

  def up do
    alter table(:previews) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :supported_platforms, {:array, :integer}, default: []
    end
  end

  def down do
    alter table(:previews) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :supported_platforms, {:array, :integer}, default: nil
    end
  end
end
