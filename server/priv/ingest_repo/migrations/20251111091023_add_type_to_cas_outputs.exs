defmodule Tuist.IngestRepo.Migrations.AddTypeToCasOutputs do
  use Ecto.Migration

  def change do
    alter table(:cas_outputs) do
      add :type, :"Nullable(String)"
    end
  end
end
