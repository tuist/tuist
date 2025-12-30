defmodule Tuist.Repo.Migrations.AddBuildVersionUniqueConstraintToAppBuilds do
  use Ecto.Migration

  def change do
    drop unique_index(:app_builds, [:binary_id])

    alter table(:app_builds) do
      add :build_version, :string
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:app_builds, [:binary_id, :build_version])
  end
end
