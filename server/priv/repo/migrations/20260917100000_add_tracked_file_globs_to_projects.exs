defmodule Tuist.Repo.Migrations.AddTrackedFileGlobsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # Null means the server defaults; an empty list means no tracked files.
      add :tracked_file_globs, {:array, :string}
    end
  end
end
