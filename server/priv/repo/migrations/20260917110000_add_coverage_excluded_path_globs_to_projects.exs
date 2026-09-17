defmodule Tuist.Repo.Migrations.AddCoverageExcludedPathGlobsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # Null means the server defaults; an empty list excludes nothing.
      add :coverage_excluded_path_globs, {:array, :string}
    end
  end
end
