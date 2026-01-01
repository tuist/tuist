defmodule Tuist.Repo.Migrations.AddBuildSystemToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :build_system, :string, default: "xcode", null: false
    end

    create index(:projects, [:build_system])
  end
end
