defmodule Tuist.Repo.Migrations.AddBundleThresholdsProjectIdIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:bundle_thresholds, [:project_id], concurrently: true)
  end
end
