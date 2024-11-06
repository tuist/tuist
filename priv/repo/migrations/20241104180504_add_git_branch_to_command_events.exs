defmodule Tuist.Repo.Migrations.AddGitBranchToCommandEvents do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add :git_branch, :string
    end
  end
end
