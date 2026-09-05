defmodule Tuist.Repo.Migrations.RemoveClusterNameFromRunnerBuildkiteInstallations do
  use Ecto.Migration

  def change do
    alter table(:runner_buildkite_installations) do
      remove :cluster_name, :string, null: false, default: ""
    end
  end
end
