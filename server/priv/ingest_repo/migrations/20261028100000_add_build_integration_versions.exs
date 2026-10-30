defmodule Tuist.IngestRepo.Migrations.AddBuildIntegrationVersions do
  use Ecto.Migration

  def change do
    for table_name <- [:build_runs, :gradle_builds, :mix_builds, :cargo_builds] do
      alter table(table_name) do
        # ClickHouse evaluates the constant default without rewriting existing parts.
        # excellent_migrations:safety-assured-for-next-line column_added_with_default
        add :tuist_version, :string, default: ""
      end
    end
  end
end
