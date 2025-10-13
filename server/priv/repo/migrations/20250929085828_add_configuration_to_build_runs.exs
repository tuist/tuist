defmodule Tuist.Repo.Migrations.AddConfigurationToBuildRuns do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      add :configuration, :string
    end
  end
end
