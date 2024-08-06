defmodule Tuist.Repo.Migrations.AddDefaultBranchToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :default_branch, :string, default: "main", null: false
    end
  end
end
