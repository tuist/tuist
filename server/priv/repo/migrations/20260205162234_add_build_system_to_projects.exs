defmodule Tuist.Repo.Migrations.AddBuildSystemToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-this-file column_added_with_default
      add :build_system, :integer, default: 0, null: false
    end
  end
end
