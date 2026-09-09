defmodule Tuist.IngestRepo.Migrations.AddHashInputsToXcodeTargets do
  use Ecto.Migration

  def change do
    alter table(:xcode_targets) do
      add :hashed_destinations, :"Array(String)", default: fragment("[]")
      add :hashed_destinations_recorded, :Bool, default: false
      add :embedded_product_references_hash, :"Nullable(String)"
      add :foreign_build_hash, :"Nullable(String)"
      add :test_device, :"Nullable(String)"
      add :test_runtime, :"Nullable(String)"
    end
  end
end
