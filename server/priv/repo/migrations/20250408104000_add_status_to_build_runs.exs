defmodule Tuist.Repo.Migrations.AddStatusToBuildRuns do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      add :status, :integer
    end
  end
end
