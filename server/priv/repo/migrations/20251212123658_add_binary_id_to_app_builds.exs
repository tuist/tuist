defmodule Tuist.Repo.Migrations.AddBinaryIdToAppBuilds do
  use Ecto.Migration

  def change do
    alter table(:app_builds) do
      add :binary_id, :string
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:app_builds, [:binary_id])
  end
end
