defmodule Tuist.IngestRepo.Migrations.RenameLegacyQuarantineEvents do
  @moduledoc """
  Renames the legacy `quarantined` / `unquarantined` event types in
  `test_case_events` to the current `muted` / `unmuted` names.

  The automations engine PR (#10232) standardized on `muted` / `unmuted`
  for state-change events, but rows written before that landed still use
  the old names. Carrying both names through every read-side query was
  noisy; rewriting the historical events lets the queries match a single
  canonical name and keeps the API enum minimal going forward.

  ## Strategy

  `event_type` is part of the table's ORDER BY key
  (`(test_case_id, event_type, id)`), so an in-place
  `ALTER TABLE ... UPDATE` is rejected by ClickHouse with
  `Cannot UPDATE key column`. The migration instead inserts a renamed
  copy of each legacy row (reusing the original `id` — the
  `event_type` change places it in a distinct keyed row, so dedup
  cannot collapse it pre-DELETE) and then deletes the original.
  Both steps run with `mutations_sync = 1` so the migration blocks
  until the rewrite is applied locally.

  ## Concurrency under multi-pod deploys

  Each pod runs `Tuist.Release.migrate` on startup
  (`server/rel/overlays/bin/start`), and ClickHouse migrations have
  `@disable_migration_lock true` because `ecto_ch` doesn't implement
  the Ecto migration-lock contract. Without serialization, two pods
  starting concurrently would both run the body — eventually
  consistent (the duplicate INSERTs share an ORDER BY key, so
  ReplacingMergeTree merges them away and the DELETE is idempotent),
  but during the merge window `Tests.list_test_case_events/2` (which
  doesn't dedup by `test_case_id` or use `FINAL`) would render the
  rename event twice on the test case detail page.

  We serialize via a Postgres advisory lock instead. Postgres is shared
  across every pod, so `pg_advisory_xact_lock` is a true cross-process
  mutex. The first pod takes the lock, applies the rewrite, releases
  on transaction end. Subsequent pods block on the lock; once they
  acquire it, the legacy rows are already gone and their INSERT /
  DELETE are no-ops.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Stable per-migration lock id. Derived from the migration version so it
  # can't collide with locks taken by other concurrency-sensitive paths.
  @lock_id 20_260_425_120_000

  def up do
    # Tuist.Repo (Postgres) is not started by `Ecto.Migrator.with_repo` when
    # running IngestRepo migrations; same bootstrap pattern as the
    # `BackfillTestRunsFromCommandEvents` migration.
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Repo.transaction(
      fn ->
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_id])

        rename_event("quarantined", "muted")
        rename_event("unquarantined", "unmuted")
      end,
      timeout: :infinity
    )
  end

  def down do
    :ok
  end

  defp rename_event(from, to) do
    Logger.info("Rewriting test_case_events.event_type #{from} -> #{to}")

    IngestRepo.query!(
      """
      INSERT INTO test_case_events (id, test_case_id, event_type, actor_id, inserted_at)
      SELECT id, test_case_id, '#{to}', actor_id, inserted_at
      FROM test_case_events
      WHERE event_type = '#{from}'
      """,
      [],
      timeout: :infinity
    )

    IngestRepo.query!(
      """
      ALTER TABLE test_case_events
      DELETE WHERE event_type = '#{from}'
      SETTINGS mutations_sync = 1
      """,
      [],
      timeout: :infinity
    )

    Logger.info("Finished rewriting #{from} -> #{to}")
  end
end
