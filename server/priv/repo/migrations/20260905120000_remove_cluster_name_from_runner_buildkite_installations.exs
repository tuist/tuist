defmodule Tuist.Repo.Migrations.RemoveClusterNameFromRunnerBuildkiteInstallations do
  use Ecto.Migration

  def change do
    alter table(:runner_buildkite_installations) do
      # Nothing deployed has ever read this column: the Buildkite lane ships
      # unreleased on this branch, so there is no rolling-deploy window in
      # which older code could still select it.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :cluster_name, :string, null: false, default: ""
    end
  end
end
