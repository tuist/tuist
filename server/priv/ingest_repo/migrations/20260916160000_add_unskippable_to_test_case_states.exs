defmodule Tuist.IngestRepo.Migrations.AddUnskippableToTestCaseStates do
  @moduledoc """
  Adds `is_unskippable` to the test case state ledger and its projection.

  An unskippable test always runs: test selection never leaves it out, however
  much passing evidence it has. Like `state` and `is_flaky` it is set through
  `test_case_events` (`marked_unskippable` / `unmarked_unskippable`) and read
  back through `test_case_states` and `test_case_current_states`, each event
  moving only its own column.

  The materialized views are replaced under new names before the old ones are
  dropped, so no insert goes unprojected in between. During the overlap both
  views project the same rows; `argMaxIf` is idempotent under duplicates, so
  the projection is unchanged.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @state_events "'muted', 'unmuted', 'skipped', 'unskipped'"
  @flaky_events "'marked_flaky', 'unmarked_flaky'"
  @unskippable_events "'marked_unskippable', 'unmarked_unskippable'"

  def up do
    execute(
      "ALTER TABLE test_case_states ADD COLUMN IF NOT EXISTS is_unskippable Nullable(Bool) AFTER is_flaky"
    )

    execute("""
    ALTER TABLE test_case_current_states
    ADD COLUMN IF NOT EXISTS is_unskippable AggregateFunction(argMaxIf, Nullable(Bool), DateTime64(6), UInt8) AFTER is_flaky
    """)

    execute("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_states_mv_v2 TO test_case_states AS
    SELECT
      project_id,
      test_case_id,
      multiIf(
        event_type = 'muted', 'muted',
        event_type = 'skipped', 'skipped',
        event_type IN ('unmuted', 'unskipped'), 'enabled',
        NULL
      ) AS state,
      if(event_type IN (#{@flaky_events}), event_type = 'marked_flaky', NULL) AS is_flaky,
      if(event_type IN (#{@unskippable_events}), event_type = 'marked_unskippable', NULL) AS is_unskippable,
      inserted_at
    FROM test_case_events
    WHERE event_type IN (#{@state_events}, #{@flaky_events}, #{@unskippable_events})
    """)

    execute("DROP VIEW IF EXISTS test_case_states_mv")

    execute("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_current_states_mv_v2 TO test_case_current_states AS
    SELECT
      project_id,
      test_case_id,
      argMaxIfState(CAST(state AS Nullable(String)), inserted_at, isNotNull(state)) AS state,
      argMaxIfState(is_flaky, inserted_at, isNotNull(is_flaky)) AS is_flaky,
      argMaxIfState(is_unskippable, inserted_at, isNotNull(is_unskippable)) AS is_unskippable
    FROM test_case_states
    GROUP BY project_id, test_case_id
    """)

    execute("DROP VIEW IF EXISTS test_case_current_states_mv")
  end

  def down do
    execute("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_states_mv TO test_case_states AS
    SELECT
      project_id,
      test_case_id,
      multiIf(
        event_type = 'muted', 'muted',
        event_type = 'skipped', 'skipped',
        event_type IN ('unmuted', 'unskipped'), 'enabled',
        NULL
      ) AS state,
      if(event_type IN (#{@flaky_events}), event_type = 'marked_flaky', NULL) AS is_flaky,
      inserted_at
    FROM test_case_events
    WHERE event_type IN (#{@state_events}, #{@flaky_events})
    """)

    execute("DROP VIEW IF EXISTS test_case_states_mv_v2")

    execute("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_current_states_mv TO test_case_current_states AS
    SELECT
      project_id,
      test_case_id,
      argMaxIfState(CAST(state AS Nullable(String)), inserted_at, isNotNull(state)) AS state,
      argMaxIfState(is_flaky, inserted_at, isNotNull(is_flaky)) AS is_flaky
    FROM test_case_states
    GROUP BY project_id, test_case_id
    """)

    execute("DROP VIEW IF EXISTS test_case_current_states_mv_v2")
    execute("ALTER TABLE test_case_current_states DROP COLUMN IF EXISTS is_unskippable")
    execute("ALTER TABLE test_case_states DROP COLUMN IF EXISTS is_unskippable")
  end
end
