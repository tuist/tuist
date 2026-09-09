defmodule Tuist.IngestRepo.Migrations.AddHashInputSnapshotsToXcodeTargets do
  use Ecto.Migration

  def change do
    alter table(:xcode_targets) do
      add :binary_cache_hash_inputs, :"Nullable(String)"
      add :selective_testing_hash_inputs, :"Nullable(String)"
    end
  end
end
