defmodule Tuist.IngestRepo.Migrations.AddDurationUsToReapiCacheEvents do
  use Ecto.Migration

  # Kura serves most action-cache lookups in well under a millisecond, so
  # `duration_ms` rounded nearly every observation to zero: per-event latency
  # read as 0ms and throughput (bytes / duration) had a zero denominator, so
  # the cache widgets rendered "No data" for builds that had in fact
  # transferred megabytes. Microseconds are the resolution the measurement
  # actually has.
  #
  # Backfilled from the millisecond column so existing rows stay comparable,
  # at the coarse resolution they were recorded with. `duration_ms` is kept
  # until every Kura node reports microseconds.
  def up do
    execute(
      "ALTER TABLE reapi_cache_events ADD COLUMN IF NOT EXISTS duration_us UInt64 DEFAULT duration_ms * 1000"
    )
  end

  def down do
    execute("ALTER TABLE reapi_cache_events DROP COLUMN IF EXISTS duration_us")
  end
end
