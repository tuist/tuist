defmodule Tuist.Repo.Migrations.AddCustomMetadataToBuildRuns do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :custom_tags, {:array, :string}, default: []
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :custom_values, :map, default: %{}
    end

    # Hypertables don't support creating indexes concurrently
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:build_runs, [:custom_tags], using: "GIN")
  end
end
