defmodule Tuist.Repo.Migrations.AddCustomMetadataToBuildRuns do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      add :custom_tags, {:array, :string}, default: []
      add :custom_values, :map, default: %{}
    end

    create index(:build_runs, [:custom_tags], using: "GIN")
  end
end
