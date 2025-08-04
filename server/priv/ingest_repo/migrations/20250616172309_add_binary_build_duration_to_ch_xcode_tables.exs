defmodule Tuist.ClickHouseRepo.Migrations.AddBinaryBuildDurationToChXcodeTables do
  use Ecto.Migration

  def change do
    alter table(:xcode_graphs) do
      add :binary_build_duration, :"Nullable(UInt32)"
    end

    alter table(:xcode_targets) do
      add :binary_build_duration, :"Nullable(UInt32)"
    end
  end
end
