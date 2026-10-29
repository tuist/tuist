defmodule Tuist.IngestRepo.Migrations.AddBinaryCacheInstrumentedToXcodeTargets do
  use Ecto.Migration

  # Whether a target the run took from the binary cache carried coverage
  # counters. Null for a target built from source and for runs of clients
  # that reported nothing, whose hits count as uninstrumented.
  def change do
    alter table(:xcode_targets) do
      add :binary_cache_instrumented, :"Nullable(Bool)"
    end
  end
end
