defmodule Tuist.Repo.Migrations.AddLaunchArgumentGroupsToQaRuns do
  use Ecto.Migration

  def change do
    alter table(:qa_runs) do
      add :launch_argument_groups, :jsonb, default: "[]"
    end
  end
end
