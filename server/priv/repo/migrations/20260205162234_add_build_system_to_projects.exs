defmodule Tuist.Repo.Migrations.AddBuildSystemToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :build_system, :integer, default: 0, null: false
    end
  end
end
