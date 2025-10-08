defmodule Tuist.Repo.Migrations.AddPathToXcodeProjects do
  use Ecto.Migration

  def up do
    alter table(:xcode_projects) do
      add :path, :string, null: false
    end
  end

  def down do
    # Table was dropped by later migration, nothing to rollback
    :ok
  end
end
