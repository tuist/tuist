defmodule Tuist.Repo.Migrations.AddSupportedArchitecturesToAppBuilds do
  use Ecto.Migration

  def change do
    alter table(:app_builds) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :supported_architectures, {:array, :text}, default: [], null: false
    end
  end
end
