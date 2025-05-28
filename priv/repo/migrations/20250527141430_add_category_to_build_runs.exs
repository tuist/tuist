defmodule Tuist.Repo.Migrations.AddCategoryToBuildRuns do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      add :category, :integer
    end
  end
end
