defmodule Tuist.Repo.Migrations.AddBuildSystemToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :build_systems, {:array, :integer}, default: [0], null: false
      add :generated_project, :boolean, default: false, null: false
    end

    create index(:projects, [:build_systems], using: :gin)
    create index(:projects, [:generated_project])
  end
end
