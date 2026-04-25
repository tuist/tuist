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
  `Cannot UPDATE key column`. Instead we rewrite each legacy row as a
  new row with the renamed `event_type` and then delete the original.
  Both steps run with `mutations_sync = 1` so the migration blocks
  until the local replica has finished applying the rewrite — the
  service can rely on the new names the moment the migration returns.

  Reusing the original `id` is safe because the ORDER BY key includes
  `event_type`: the renamed copy and the original occupy distinct keyed
  rows during the brief window between INSERT and DELETE, so dedup
  cannot collapse them.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    rename_event("quarantined", "muted")
    rename_event("unquarantined", "unmuted")
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
