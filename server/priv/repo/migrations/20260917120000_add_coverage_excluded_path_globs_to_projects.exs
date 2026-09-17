defmodule Tuist.Repo.Migrations.AddCoverageExcludedPathGlobsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # Null or empty: nothing is excluded.
      add :coverage_excluded_path_globs, {:array, :string}
    end
  end
end
