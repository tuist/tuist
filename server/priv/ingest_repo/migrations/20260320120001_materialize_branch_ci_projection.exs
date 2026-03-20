defmodule Tuist.IngestRepo.Migrations.MaterializeBranchCiProjection do
  @moduledoc """
  Materializes the `proj_by_branch_ci` projection for existing data parts.
  New data inserted after the ADD PROJECTION migration is automatically projected.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!(
      "ALTER TABLE test_case_runs MATERIALIZE PROJECTION IF EXISTS proj_by_branch_ci SETTINGS mutations_sync = 1",
      [],
      timeout: 1_200_000
    )
  end

  def down do
    :ok
  end
end
