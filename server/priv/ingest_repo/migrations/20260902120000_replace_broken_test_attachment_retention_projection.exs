defmodule Tuist.IngestRepo.Migrations.ReplaceBrokenTestAttachmentRetentionProjection do
  @moduledoc """
  Replaces `proj_artifact_retention_by_test_run_inserted_at` on
  `test_case_run_attachments`, which no part can read.

  A projection's `ORDER BY` resolves against the parent table's columns, not
  against aliases introduced in the projection's `SELECT`. `20260529100000`
  wrote `assumeNotNull(test_run_id) AS test_run_id ... ORDER BY test_run_id`,
  so the key bound to the table's `test_run_id Nullable(UUID)` and the
  `assumeNotNull` applied only to the stored column. ClickHouse accepted the
  statement because the alias shadows a real column; an alias under any other
  name is rejected with `UNKNOWN_IDENTIFIER`.

  The write path then serializes `primary.cidx` at 25 bytes per mark
  (`Nullable(UUID)` plus `DateTime64(6)`) while the read path types the same
  name through the projection's `SELECT` as `UUID` and consumes 24, so every
  read of a part carrying the projection fails with `Code: 4 ... primary.cidx
  is unexpectedly long (EXPECTED_END_OF_FILE)`. Since the 30 day cutoff first
  reached a partition holding the projection, that has failed
  `Tuist.Storage.ExpiredArtifacts.delete_test_attachments/3` for every account
  whose scan range reaches such a part, freezing those accounts' rows in
  `artifact_retention_cursors`.

  `(test_run_id, inserted_at)` could not serve that sweep in any case: it scans
  `inserted_at < cutoff` and pages by `ORDER BY inserted_at, id`. The
  replacement keys on those two columns, both non-nullable, so no expression is
  needed in the projection at all.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_run_attachments
    DROP PROJECTION IF EXISTS proj_artifact_retention_by_test_run_inserted_at
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_run_attachments
    ADD PROJECTION IF NOT EXISTS proj_artifact_retention_by_inserted_at (
      SELECT id, test_run_id, test_case_run_id, file_name, inserted_at
      ORDER BY inserted_at, id
    )
    """
  end

  def down do
    # The projection this replaces makes the table unreadable, so rolling back
    # only removes the replacement.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_run_attachments
    DROP PROJECTION IF EXISTS proj_artifact_retention_by_inserted_at
    """
  end
end
