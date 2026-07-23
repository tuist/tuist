defmodule Tuist.IngestRepo.Migrations.CreateTestCaseStatesMv do
  use Ecto.Migration

  # Maintains `test_case_states` as a projection of `test_case_events`.
  #
  # This is what removes the second writer. Previously the control plane wrote
  # the state and the event ledger separately, two unsynchronised inserts that
  # could drift, and ingestion wrote the same columns on `test_cases` and could
  # revert them. Now the ledger is the only thing anyone writes and the state
  # falls out of it.
  #
  # ## One column per row
  #
  # Each event changes exactly one of the two columns, so each row sets that one
  # and leaves the other NULL. Reads resolve them separately with
  # `argMaxIf(..., isNotNull(...))`.
  #
  # Writing both columns on every row is what the original bug was, in a
  # different costume: a `marked_flaky` event would carry whatever `state` the
  # view happened to see and overwrite a concurrent mute. Leaving the untouched
  # column NULL means an event can only ever move the column it is about.
  #
  # ## Events without a project
  #
  # Pods still running the release before this one insert events without a
  # `project_id`, so the column defaults to 0 and the projected row is invisible
  # to the project-scoped reads. Those rows are deliberately *not* filtered out
  # here. They are inert rather than wrong, and leaving them makes the loss
  # countable and repairable with a join back to `test_cases`, where a `WHERE`
  # that dropped them would erase the evidence. Silently discarding state
  # writes is the failure this whole change exists to remove.
  #
  # The invariant is enforced where it can be enforced loudly instead:
  # `Tuist.Tests.record_test_case_events/4` raises rather than writing an event
  # with no project.
  #
  # ## Rollout
  #
  # Creating a materialized view does not backfill: it only sees inserts that
  # happen after it exists. That is deliberate and load-bearing here. Every
  # event already in the table stays out of the projection, and the release that
  # cuts reads over seeds the starting values explicitly. If creation *did*
  # replay history it would restore ~600 mutes from February and March that
  # teams have been running without for five months.
  @state_events "'muted', 'unmuted', 'skipped', 'unskipped'"
  @flaky_events "'marked_flaky', 'unmarked_flaky'"

  def up do
    execute("""
    CREATE MATERIALIZED VIEW test_case_states_mv TO test_case_states AS
    SELECT
      project_id,
      test_case_id,
      -- Every branch is explicit and the fallback is NULL, not 'enabled'. A
      -- state event type added to `determine_test_case_events/2` without
      -- touching this view then projects nothing, which shows up as a state
      -- that won't change, rather than silently resetting the test to enabled.
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
  end

  def down do
    execute("DROP VIEW IF EXISTS test_case_states_mv")
  end
end
