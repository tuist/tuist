defmodule Tuist.IngestRepo.Migrations.SweepRemainingEuCentralRegionRows do
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  # The second pass of the eu-central to eu-west rename. The first mutation ran
  # in the pre-upgrade hook and rewrote the rows that existed then, but a Kura
  # node stamps its events with its own region and only learns the new one when
  # the reconciler re-renders its instance and rolls it. The rows written in
  # that gap kept the old id: on production, four usage events and one eviction
  # event. This sweeps them so a series grouped by region reads as one region.
  #
  # The fleet has converged, so nothing writes the old id any more and one pass
  # is enough. Idempotent regardless: a second run matches nothing.
  @tables ~w(kura_usage_events kura_eviction_events kura_storage_snapshots)

  def up, do: rename_region("eu-central", "eu-west")

  # The rename is not reversible from here: the first migration's `down` already
  # restores every row it moved, and this pass cannot tell the stragglers it
  # rewrote apart from the ones that were always eu-west.
  def down, do: :ok

  defp rename_region(from, to) do
    for table <- @tables do
      IngestRepo.query!(
        "ALTER TABLE #{table} UPDATE region = '#{to}' WHERE region = '#{from}' SETTINGS mutations_sync = 1",
        [],
        timeout: :infinity
      )
    end
  end
end
