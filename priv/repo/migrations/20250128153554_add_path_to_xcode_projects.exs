defmodule Tuist.Repo.Migrations.AddPathToXcodeProjects do
  use Ecto.Migration

  def change do
    alter table(:xcode_projects) do
      add :path, :string, null: false
    end
  end
end
