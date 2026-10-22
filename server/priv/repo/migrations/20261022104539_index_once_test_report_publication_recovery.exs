defmodule Tuist.Repo.Migrations.IndexOnceTestReportPublicationRecovery do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:once_test_report_publications, [:state, :updated_at], concurrently: true)
  end
end
