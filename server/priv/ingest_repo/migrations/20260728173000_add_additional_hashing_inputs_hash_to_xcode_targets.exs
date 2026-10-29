defmodule Tuist.IngestRepo.Migrations.AddAdditionalHashingInputsHashToXcodeTargets do
  use Ecto.Migration

  def change do
    alter table(:xcode_targets) do
      add :additional_hashing_inputs_hash, :string, default: ""
    end
  end
end
