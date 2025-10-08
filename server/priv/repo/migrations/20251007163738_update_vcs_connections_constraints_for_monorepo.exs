defmodule Tuist.Repo.Migrations.UpdateVcsConnectionsConstraintsForMonorepo do
  use Ecto.Migration

  def change do
    # Drop the existing unique index on [:provider, :project_id]
    drop unique_index(:vcs_connections, [:provider, :project_id])

    # Create new unique index on [:project_id] only
    # This maintains "1 Tuist project -> max 1 GitHub repo" constraint
    # while allowing "1 GitHub repo -> multiple Tuist projects" (monorepo support)
    create unique_index(:vcs_connections, [:project_id])
  end
end
