defmodule Tuist.IngestRepo.Migrations.RenameEuCentralRegionToEuWest do
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  # The analytics side of the Postgres migration with the same stamp. It
  # rewrites the rows that exist when it runs. A Kura node stamps its events
  # with its own region, so what the instances send between this mutation and
  # their roll onto the renamed catalog entry still carries the old id; the
  # follow-up migration that retires the gateway's transitional class alias
  # runs these same statements once more, after the fleet has converged.
  # These are small tables with no projections, so a synchronous mutation is
  # cheap.
  @tables ~w(kura_usage_events kura_eviction_events kura_storage_snapshots)

  def up, do: rename_region("eu-central", "eu-west")
  def down, do: rename_region("eu-west", "eu-central")

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
