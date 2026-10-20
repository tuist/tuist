defmodule Tuist.IngestRepo.Migrations.RemoveCommandEventsLegacyIdDefault do
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  # `legacy_id` was created with a server-generated default, first
  # `abs(rand64())` and then `generateSerialID('command_events_legacy_id')`
  # where a Keeper is available. Both are filled by whichever server executes
  # the insert, so two servers taking the same write produce two different
  # values for the same row.
  #
  # That is visible now: the canary parity check reports `command_events` with
  # identical rows, timestamps and every other column sum on both sides, and
  # `sum_legacy_id` 28094 against 838. The gap is not drift. Cloud's counter
  # has been running since 2025; the in-cluster server's started at zero when
  # its database was created.
  #
  # It matters at the cutover rather than now. Once the in-cluster server is
  # the system of record, its counter is both unrelated to the old one and far
  # behind it, so it would re-issue values that historical rows already hold.
  # A collision, not an error.
  #
  # Removing the default makes the column deterministic: no writer sets it, so
  # both servers store the type's zero. Rows written before this keep the value
  # they already have, which the backfill copied faithfully.
  #
  # `REMOVE DEFAULT` rather than restating the type, because it is metadata
  # only. Restating the type risks changing it, and `command_events` carries a
  # projection naming this column plus materialized views built with
  # `SELECT *`, so anything that rewrites parts is expensive and hard to undo.
  # Dropping the column outright is that kind of change and is deliberately not
  # what this does; nothing in this repository reads `legacy_id`, so it can go
  # later, on its own, once external consumers are ruled out.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    # Metadata-only: it neither rewrites parts nor touches the column's type.
    IngestRepo.query!("ALTER TABLE command_events MODIFY COLUMN legacy_id REMOVE DEFAULT", [],
      timeout: :infinity
    )
  end

  def down do
    default =
      if Tuist.ClickHouseCapabilities.use_serial_ids?(repo()) do
        "generateSerialID('command_events_legacy_id')"
      else
        "abs(rand64())"
      end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!(
      "ALTER TABLE command_events MODIFY COLUMN legacy_id DEFAULT #{default}",
      [],
      timeout: :infinity
    )
  end
end
