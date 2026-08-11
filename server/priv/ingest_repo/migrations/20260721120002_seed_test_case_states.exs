defmodule Tuist.IngestRepo.Migrations.SeedTestCaseStates do
  use Ecto.Migration

  # Gives `test_case_states` its starting values.
  #
  # The materialized view added in the previous release only sees events
  # inserted after it was created, so on its own the projection knows nothing
  # about test cases that were muted before then. This seeds that floor, and it
  # is the only write to this table that isn't the view.
  #
  # ## Where the values come from
  #
  # Mostly from the legacy `state` / `is_flaky` columns on `test_cases`, which
  # are correct for the vast majority of test cases.
  #
  # They are not correct for the ones this whole change exists to fix: where
  # ingestion clobbered a mute, the snapshot says `enabled`. For those the
  # event ledger is the authority, so recent state and flaky events override
  # the snapshot. Each column is taken from its own event stream, never from a
  # single "latest event", because resolving both from one event is the lost
  # update being fixed.
  #
  # ## Why only recent events
  #
  # 633 test cases currently disagree with their own event history, but ~96% of
  # them were muted in February and March and have been running ever since.
  # Silently re-muting hundreds of tests that teams have lived without for five
  # months is a larger and less welcome change than leaving them, and an event
  # that old is weak evidence of present intent. The cutoff is an absolute date
  # rather than a relative window so this means the same thing whenever it runs.
  #
  # ## Why the floor is stamped in the past
  #
  # Control-plane changes made between the previous release and this one are
  # already in the table, projected by the view and stamped with their event
  # time. The seed must lose to those, otherwise it would revert a mute someone
  # made during the rollout. Stamping it before the previous release could have
  # deployed guarantees that: every projected row is newer, so it wins, and the
  # seed only fills in test cases the view never saw.
  #
  # Re-running is harmless for the same reason. The floor never outranks a
  # projected row, and a second identical row resolves to the same value. That
  # is also why this takes no advisory lock, unlike the sibling migration that
  # adds `project_id`: every pod runs the same statement, duplicate rows are
  # value-identical, and a row a racing pod writes is either identical or
  # already superseded by a projected one.
  @floor "2026-07-21 00:00:00"
  @cutoff "2026-07-01 00:00:00"
  @state_events "'muted', 'unmuted', 'skipped', 'unskipped'"
  @flaky_events "'marked_flaky', 'unmarked_flaky'"
  @max_threads 4
  @max_memory_bytes 4 * 1024 * 1024 * 1024

  def up do
    execute("""
    INSERT INTO test_case_states (project_id, test_case_id, state, is_flaky, inserted_at)
    WITH
      legacy AS (
        SELECT project_id, id AS test_case_id, state, is_flaky
        FROM test_cases FINAL
        WHERE state != 'enabled' OR is_flaky = true
      ),
      recent_state AS (
        SELECT test_case_id, argMax(event_type, inserted_at) AS last_event
        FROM test_case_events
        WHERE event_type IN (#{@state_events})
        GROUP BY test_case_id
        HAVING max(inserted_at) >= toDateTime64('#{@cutoff}', 6)
      ),
      recent_flaky AS (
        SELECT test_case_id, argMax(event_type, inserted_at) AS last_event
        FROM test_case_events
        WHERE event_type IN (#{@flaky_events})
        GROUP BY test_case_id
        HAVING max(inserted_at) >= toDateTime64('#{@cutoff}', 6)
      ),
      candidates AS (
        SELECT id, any(project_id) AS project_id
        FROM test_cases
        WHERE id IN (SELECT test_case_id FROM legacy)
           OR id IN (SELECT test_case_id FROM recent_state)
           OR id IN (SELECT test_case_id FROM recent_flaky)
        GROUP BY id
      )
    SELECT project_id, test_case_id, seed_state, seed_is_flaky, toDateTime64('#{@floor}', 6)
    FROM (
      SELECT
        candidates.project_id AS project_id,
        candidates.id AS test_case_id,
        -- ClickHouse fills an unmatched LEFT JOIN side with the type's zero
        -- value, not a null, so an absent legacy row reads as an empty state.
        if(legacy.state = '', 'enabled', legacy.state) AS legacy_state,
        legacy.is_flaky AS legacy_is_flaky,
        if(
          recent_state.last_event = '',
          legacy_state,
          multiIf(
            recent_state.last_event = 'muted', 'muted',
            recent_state.last_event = 'skipped', 'skipped',
            'enabled'
          )
        ) AS seed_state,
        if(
          recent_flaky.last_event = '',
          legacy_is_flaky,
          recent_flaky.last_event = 'marked_flaky'
        ) AS seed_is_flaky
      FROM candidates
      LEFT JOIN legacy ON legacy.test_case_id = candidates.id
      LEFT JOIN recent_state ON recent_state.test_case_id = candidates.id
      LEFT JOIN recent_flaky ON recent_flaky.test_case_id = candidates.id
    )
    WHERE seed_state != 'enabled' OR seed_is_flaky = true
    SETTINGS max_threads = #{@max_threads},
             max_memory_usage = #{@max_memory_bytes}
    """)
  end

  def down do
    execute(
      "ALTER TABLE test_case_states DELETE WHERE inserted_at = toDateTime64('#{@floor}', 6)"
    )
  end
end
