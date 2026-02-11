defmodule Tuist.IngestRepo.Migrations.BackfillMissingUnquarantinedEvents do
  @moduledoc """
  Backfills missing "unquarantined" events for test cases that were silently
  unquarantined during ingestion before PR #9397 fixed the is_quarantined
  preservation bug.

  Before the fix, `create_test_cases` did not preserve the `is_quarantined`
  field from existing test case records, so every test run ingestion would
  reset quarantined test cases to `is_quarantined: false` without creating
  an "unquarantined" event. This left the events table out of sync with the
  actual test case state, causing the quarantined tests chart to show
  inflated counts.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    Logger.info("Backfilling missing unquarantined events...")

    # Find test cases where:
    # 1. The latest quarantine-related event is "quarantined"
    # 2. But the latest TestCase record has is_quarantined = false
    stale_quarantined =
      IngestRepo.query!(
        """
        SELECT
          e.test_case_id,
          e.last_quarantined_at
        FROM (
          SELECT
            test_case_id,
            argMax(event_type, inserted_at) AS last_event_type,
            max(inserted_at) AS last_quarantined_at
          FROM test_case_events
          WHERE event_type IN ('quarantined', 'unquarantined')
          GROUP BY test_case_id
          HAVING last_event_type = 'quarantined'
        ) e
        JOIN (
          SELECT
            id,
            argMax(is_quarantined, inserted_at) AS current_is_quarantined
          FROM test_cases
          GROUP BY id
        ) tc ON e.test_case_id = tc.id
        WHERE tc.current_is_quarantined = false
        """,
        [],
        timeout: 60_000
      )

    rows = stale_quarantined.rows

    if Enum.empty?(rows) do
      Logger.info("No stale quarantined events found, nothing to backfill")
    else
      Logger.info("Found #{length(rows)} test cases with missing unquarantined events")

      events =
        Enum.map(rows, fn [test_case_id, last_quarantined_at] ->
          # Timestamp the unquarantined event 1 second after the last quarantined event
          inserted_at = NaiveDateTime.add(last_quarantined_at, 1, :second)

          %{
            id: Ecto.UUID.generate(),
            test_case_id: test_case_id,
            event_type: "unquarantined",
            actor_id: nil,
            inserted_at: inserted_at
          }
        end)

      IngestRepo.insert_all("test_case_events", events,
        types: %{
          id: :uuid,
          test_case_id: :uuid,
          event_type: "LowCardinality(String)",
          actor_id: "Nullable(Int64)",
          inserted_at: "DateTime64(6)"
        }
      )

      Logger.info("Inserted #{length(events)} unquarantined events")
    end
  end

  def down do
    :ok
  end
end
