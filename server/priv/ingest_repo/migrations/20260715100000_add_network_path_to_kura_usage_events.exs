defmodule Tuist.IngestRepo.Migrations.AddNetworkPathToKuraUsageEvents do
  use Ecto.Migration

  def up do
    alter table(:kura_usage_events) do
      add :network_path, :string, default: "unknown"
    end
  end

  def down do
    alter table(:kura_usage_events) do
      remove :network_path
    end
  end
end
