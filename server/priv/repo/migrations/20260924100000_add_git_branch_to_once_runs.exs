defmodule Tuist.Repo.Migrations.AddGitBranchToOnceRuns do
  use Ecto.Migration

  # `once_runs` is introduced by the same unreleased change, so there is no
  # populated table to lock and no concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file column_added_with_default
  # excellent_migrations:safety-assured-for-this-file index_not_concurrently

  def change do
    alter table(:once_runs) do
      add :git_branch, :string, size: 255, default: "", null: false
    end

    create index(:once_runs, [:project_id, :git_branch])
  end
end
