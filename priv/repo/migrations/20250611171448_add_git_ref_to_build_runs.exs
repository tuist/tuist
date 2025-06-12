defmodule Tuist.Repo.Migrations.AddGitRefToBuildRuns do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      add :git_ref, :string
    end
  end
end
